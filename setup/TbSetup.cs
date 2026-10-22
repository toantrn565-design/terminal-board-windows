// Terminal Board Setup: a one-file installer.
//
// The install kit is embedded in this exe as payload.zip. Setup unpacks it to a temp folder and
// runs install.ps1 from there (hidden), so it does exactly what install.ps1 does, with a window
// around it. Nothing needs administrator rights: everything is installed for the current user.
//
// Switches:
//   /S                          silent install, no window (exit code 0 = installed, 3 = Windows Terminal missing)
//   /extract <folder>           only unpack the embedded kit into <folder>
//   /snapshot <png> [state]     draw the window to a picture; state is ready, installing, done, needswt or failed
//
// Written in C# 5 on purpose: it is built with the csc.exe that ships with Windows.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;

namespace TerminalBoardSetup
{
    internal enum Outcome
    {
        Success,
        NeedsWindowsTerminal,
        Failed
    }

    internal sealed class InstallResult
    {
        public Outcome Outcome;
        public string Summary;
        public string Log;
    }

    // ---- the install kit inside this exe ----

    internal static class Payload
    {
        public static void ExtractTo(string directory)
        {
            Directory.CreateDirectory(directory);
            string root = Path.GetFullPath(directory).TrimEnd('\\') + "\\";

            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (stream == null)
                {
                    throw new InvalidOperationException("This setup file is damaged: the install files are missing.");
                }

                using (ZipArchive zip = new ZipArchive(stream, ZipArchiveMode.Read))
                {
                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        string relative = entry.FullName.Replace('/', '\\');
                        string target = Path.GetFullPath(Path.Combine(directory, relative));
                        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                        {
                            throw new InvalidOperationException("This setup file is damaged: " + entry.FullName);
                        }
                        if (relative.EndsWith("\\"))
                        {
                            Directory.CreateDirectory(target);
                            continue;
                        }
                        Directory.CreateDirectory(Path.GetDirectoryName(target));
                        entry.ExtractToFile(target, true);
                    }
                }
            }
        }
    }

    // ---- running install.ps1 ----

    internal static class Installer
    {
        const int TimeoutMilliseconds = 5 * 60 * 1000;

        public static string InstallDirectory
        {
            get
            {
                string localAppData = Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? string.Empty;
                return Path.Combine(localAppData, "Microsoft", "WindowsApps", "TerminalBoard");
            }
        }

        public static string HelperPath
        {
            get { return Path.Combine(InstallDirectory, "TbClipboardHelper.exe"); }
        }

        public static string LogPath
        {
            get { return Path.Combine(Path.GetTempPath(), "TerminalBoardSetup.log"); }
        }

        static string PowerShellPath()
        {
            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            // A 32-bit setup on 64-bit Windows would otherwise get the 32-bit PowerShell.
            string native = Path.Combine(windows, "Sysnative", "WindowsPowerShell", "v1.0", "powershell.exe");
            if (Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess && File.Exists(native))
            {
                return native;
            }
            return Path.Combine(windows, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        }

        public static InstallResult Run(string version)
        {
            StringBuilder log = new StringBuilder();
            InstallResult result = new InstallResult();
            string temp = Path.Combine(Path.GetTempPath(), "TerminalBoardSetup-" + Guid.NewGuid().ToString("N"));

            try
            {
                log.AppendLine("Terminal Board Setup " + version + "  " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));
                Payload.ExtractTo(temp);

                ProcessStartInfo info = new ProcessStartInfo();
                info.FileName = PowerShellPath();
                info.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(temp, "install.ps1") + "\" -Version \"" + version + "\"";
                info.WorkingDirectory = temp;
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                info.RedirectStandardInput = true;
                info.RedirectStandardOutput = true;
                info.RedirectStandardError = true;

                using (Process process = Process.Start(info))
                {
                    process.StandardInput.Close();
                    DataReceivedEventHandler collect = delegate(object sender, DataReceivedEventArgs e)
                    {
                        if (e.Data != null)
                        {
                            lock (log)
                            {
                                log.AppendLine(e.Data);
                            }
                        }
                    };
                    process.OutputDataReceived += collect;
                    process.ErrorDataReceived += collect;
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();

                    if (!process.WaitForExit(TimeoutMilliseconds))
                    {
                        try
                        {
                            process.Kill();
                        }
                        catch (Exception)
                        {
                        }
                        result.Outcome = Outcome.Failed;
                        result.Summary = "Setup took too long and was stopped.";
                    }
                    else
                    {
                        process.WaitForExit();   // lets the last output lines arrive
                        result = Judge(process.ExitCode, log);
                    }
                }
            }
            catch (Exception ex)
            {
                result.Outcome = Outcome.Failed;
                result.Summary = "Setup could not start: " + ex.Message;
                lock (log)
                {
                    log.AppendLine(ex.ToString());
                }
            }
            finally
            {
                CleanUp(temp);
            }

            string text;
            lock (log)
            {
                text = log.ToString();
            }
            result.Log = text;
            try
            {
                File.WriteAllText(LogPath, text, new UTF8Encoding(false));
            }
            catch (Exception)
            {
            }
            return result;
        }

        static InstallResult Judge(int exitCode, StringBuilder log)
        {
            InstallResult result = new InstallResult();
            string text;
            lock (log)
            {
                text = log.ToString();
            }

            if (exitCode == 0 && File.Exists(HelperPath))
            {
                result.Outcome = Outcome.Success;
            }
            else if (text.IndexOf("Windows Terminal (wt.exe) was not found", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                result.Outcome = Outcome.NeedsWindowsTerminal;
            }
            else if (exitCode == 0)
            {
                result.Outcome = Outcome.Failed;
                result.Summary = "Terminal Board was copied, but its settings screen could not be built on this PC.";
            }
            else
            {
                result.Outcome = Outcome.Failed;
                result.Summary = "Setup stopped before it finished.";
            }
            return result;
        }

        static void CleanUp(string directory)
        {
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    if (Directory.Exists(directory))
                    {
                        Directory.Delete(directory, true);
                    }
                    return;
                }
                catch (Exception)
                {
                    Thread.Sleep(300);   // antivirus may still be looking at a file
                }
            }
        }

        public static void OpenTerminalBoard()
        {
            try
            {
                Process.Start(HelperPath, "--desk");
            }
            catch (Exception)
            {
            }
        }

        public static void OpenStore()
        {
            try
            {
                ProcessStartInfo store = new ProcessStartInfo("ms-windows-store://pdp/?productid=9N0DX20HK701");
                store.UseShellExecute = true;
                Process.Start(store);
            }
            catch (Exception)
            {
                try
                {
                    ProcessStartInfo web = new ProcessStartInfo("https://aka.ms/terminal");
                    web.UseShellExecute = true;
                    Process.Start(web);
                }
                catch (Exception)
                {
                }
            }
        }
    }

    // ---- the window ----

    internal sealed class SetupWindow
    {
        const string Xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Terminal Board Setup' SizeToContent='WidthAndHeight' ResizeMode='NoResize'
        WindowStartupLocation='CenterScreen' FontFamily='Segoe UI' UseLayoutRounding='True' SnapsToDevicePixels='True'>
  <Window.Resources>
    <Style x:Key='PrimaryButton' TargetType='Button'>
      <Setter Property='Foreground' Value='#FFD86B'/>
      <Setter Property='FontSize' Value='14'/>
      <Setter Property='FontWeight' Value='SemiBold'/>
      <Setter Property='Padding' Value='28,0'/>
      <Setter Property='Height' Value='44'/>
      <Setter Property='Cursor' Value='Hand'/>
      <Setter Property='Template'>
        <Setter.Value>
          <ControlTemplate TargetType='Button'>
            <Border x:Name='Box' CornerRadius='10' BorderThickness='1' BorderBrush='#99FFD86B' Padding='{TemplateBinding Padding}'>
              <Border.Background>
                <LinearGradientBrush StartPoint='0,0' EndPoint='1,1'>
                  <GradientStop Color='#4F3411' Offset='0'/>
                  <GradientStop Color='#1F1405' Offset='1'/>
                </LinearGradientBrush>
              </Border.Background>
              <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property='IsMouseOver' Value='True'>
                <Setter TargetName='Box' Property='BorderBrush' Value='#FFE29A'/>
              </Trigger>
              <Trigger Property='IsEnabled' Value='False'>
                <Setter TargetName='Box' Property='Opacity' Value='0.45'/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key='GhostButton' TargetType='Button'>
      <Setter Property='Foreground' Value='#2A1A04'/>
      <Setter Property='FontSize' Value='14'/>
      <Setter Property='Padding' Value='24,0'/>
      <Setter Property='Height' Value='44'/>
      <Setter Property='Cursor' Value='Hand'/>
      <Setter Property='Template'>
        <Setter.Value>
          <ControlTemplate TargetType='Button'>
            <Border x:Name='Box' CornerRadius='10' BorderThickness='1' BorderBrush='#7A5A1E' Background='Transparent' Padding='{TemplateBinding Padding}'>
              <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property='IsMouseOver' Value='True'>
                <Setter TargetName='Box' Property='Background' Value='#40FFFFFF'/>
              </Trigger>
              <Trigger Property='IsEnabled' Value='False'>
                <Setter TargetName='Box' Property='Opacity' Value='0.45'/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid x:Name='Root' Width='580'>
    <Grid.Background>
      <LinearGradientBrush StartPoint='0,0' EndPoint='1,1'>
        <GradientStop Color='#F8E7A6' Offset='0'/>
        <GradientStop Color='#E3B650' Offset='0.5'/>
        <GradientStop Color='#A8711A' Offset='1'/>
      </LinearGradientBrush>
    </Grid.Background>
    <Grid Margin='32,28,32,28'>
      <Grid.RowDefinitions>
        <RowDefinition Height='Auto'/>
        <RowDefinition Height='*'/>
        <RowDefinition Height='Auto'/>
      </Grid.RowDefinitions>
      <StackPanel Orientation='Horizontal' Margin='0,0,0,20'>
        <Image x:Name='Logo' Width='56' Height='56' Margin='0,0,16,0' RenderOptions.BitmapScalingMode='HighQuality'/>
        <StackPanel VerticalAlignment='Center'>
          <TextBlock Text='Terminal Board' FontSize='28' FontWeight='SemiBold' Foreground='#2A1A04'/>
          <TextBlock x:Name='Subtitle' FontSize='13' Foreground='#6A4B12' Margin='0,2,0,0'/>
        </StackPanel>
      </StackPanel>
      <Border Grid.Row='1' CornerRadius='14' Background='#E62A1B08' BorderBrush='#99FFD86B' BorderThickness='1' Padding='26,22' MinHeight='210'>
        <StackPanel>
          <TextBlock x:Name='Heading' FontSize='20' FontWeight='SemiBold' Foreground='#FFF6DC'/>
          <TextBlock x:Name='Message' Margin='0,10,0,0' TextWrapping='Wrap' FontSize='14' LineHeight='21' Foreground='#D8C48E'/>
          <StackPanel x:Name='Bullets' Margin='0,14,0,0'/>
          <Border x:Name='ProgressTrack' Height='6' CornerRadius='3' Background='#33FFFFFF' Margin='0,20,0,0' ClipToBounds='True' Visibility='Collapsed'>
            <Border x:Name='Runner' Width='140' HorizontalAlignment='Left' CornerRadius='3' Background='#FFD86B'>
              <Border.RenderTransform>
                <TranslateTransform x:Name='RunnerMove' X='-140'/>
              </Border.RenderTransform>
            </Border>
          </Border>
          <TextBox x:Name='LogBox' Margin='0,16,0,0' Height='170' IsReadOnly='True' TextWrapping='Wrap' FontFamily='Consolas' FontSize='11.5'
                   Background='#F0140D03' Foreground='#EFE3BB' BorderThickness='0' Padding='10'
                   VerticalScrollBarVisibility='Auto' Visibility='Collapsed'/>
        </StackPanel>
      </Border>
      <StackPanel Grid.Row='2' Orientation='Horizontal' HorizontalAlignment='Right' Margin='0,20,0,0'>
        <Button x:Name='BtnSecondary' Style='{StaticResource GhostButton}' Margin='0,0,12,0'/>
        <Button x:Name='BtnPrimary' Style='{StaticResource PrimaryButton}'/>
      </StackPanel>
    </Grid>
  </Grid>
</Window>";

        readonly Window window;
        readonly string version;
        readonly Grid root;
        readonly TextBlock subtitle;
        readonly TextBlock heading;
        readonly TextBlock message;
        readonly StackPanel bullets;
        readonly Border progressTrack;
        readonly TranslateTransform runnerMove;
        readonly TextBox logBox;
        readonly Button primary;
        readonly Button secondary;
        Action primaryAction;
        Action secondaryAction;
        bool busy;

        public Window Window
        {
            get { return window; }
        }

        public SetupWindow(string version)
        {
            this.version = version;
            window = (Window)XamlReader.Parse(Xaml);
            root = (Grid)window.FindName("Root");
            subtitle = (TextBlock)window.FindName("Subtitle");
            heading = (TextBlock)window.FindName("Heading");
            message = (TextBlock)window.FindName("Message");
            bullets = (StackPanel)window.FindName("Bullets");
            progressTrack = (Border)window.FindName("ProgressTrack");
            runnerMove = (TranslateTransform)window.FindName("RunnerMove");
            logBox = (TextBox)window.FindName("LogBox");
            primary = (Button)window.FindName("BtnPrimary");
            secondary = (Button)window.FindName("BtnSecondary");

            LoadLogo((Image)window.FindName("Logo"));

            primary.IsDefault = true;
            primary.Click += delegate
            {
                if (primaryAction != null)
                {
                    primaryAction();
                }
            };
            secondary.Click += delegate
            {
                if (secondaryAction != null)
                {
                    secondaryAction();
                }
            };
            window.Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e)
            {
                if (busy)
                {
                    e.Cancel = true;   // do not walk away in the middle of an install
                }
            };

            ShowReady();
        }

        void LoadLogo(Image target)
        {
            try
            {
                using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("logo.ico"))
                {
                    if (stream == null)
                    {
                        return;
                    }
                    BitmapDecoder decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                    BitmapFrame best = decoder.Frames.OrderByDescending(delegate(BitmapFrame frame) { return frame.PixelWidth; }).First();
                    target.Source = best;
                    window.Icon = best;
                }
            }
            catch (Exception)
            {
            }
        }

        static SolidColorBrush Solid(string hex)
        {
            SolidColorBrush brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            brush.Freeze();
            return brush;
        }

        // ---- states ----

        public void ShowState(string state)
        {
            switch ((state ?? "ready").ToLowerInvariant())
            {
                case "installing":
                    ShowInstalling(File.Exists(Installer.HelperPath));
                    break;
                case "done":
                    ShowDone();
                    break;
                case "needswt":
                    ShowNeedsWindowsTerminal();
                    break;
                case "failed":
                    ShowFailed("Setup stopped before it finished.",
                        "install.ps1 : Something went wrong here (sample text for the picture).\r\nWARNING: Could not draw the icon.\r\nThe full log is saved to " + Installer.LogPath);
                    break;
                default:
                    ShowReady();
                    break;
            }
        }

        void SetButtons(string primaryText, Action onPrimary, string secondaryText, Action onSecondary)
        {
            primary.Content = primaryText;
            primary.Visibility = primaryText == null ? Visibility.Collapsed : Visibility.Visible;
            primaryAction = onPrimary;
            secondary.Content = secondaryText;
            secondary.Visibility = secondaryText == null ? Visibility.Collapsed : Visibility.Visible;
            secondaryAction = onSecondary;
        }

        void SetBullets(params string[] items)
        {
            bullets.Children.Clear();
            bullets.Visibility = items.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
            foreach (string item in items)
            {
                Grid row = new Grid();
                row.Margin = new Thickness(0, 0, 0, 8);
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                System.Windows.Shapes.Ellipse dot = new System.Windows.Shapes.Ellipse();
                dot.Width = 6;
                dot.Height = 6;
                dot.Fill = Solid("#FFD86B");
                dot.Margin = new Thickness(0, 1, 12, 0);
                dot.VerticalAlignment = VerticalAlignment.Center;

                TextBlock text = new TextBlock();
                text.Text = item;
                text.FontSize = 13.5;
                text.Foreground = Solid("#EFE3BB");
                text.TextWrapping = TextWrapping.Wrap;
                Grid.SetColumn(text, 1);

                row.Children.Add(dot);
                row.Children.Add(text);
                bullets.Children.Add(row);
            }
        }

        void StartProgress()
        {
            progressTrack.Visibility = Visibility.Visible;
            DoubleAnimation slide = new DoubleAnimation(-140, 480, TimeSpan.FromMilliseconds(1300));
            slide.RepeatBehavior = RepeatBehavior.Forever;
            runnerMove.BeginAnimation(TranslateTransform.XProperty, slide);
        }

        void StopProgress()
        {
            runnerMove.BeginAnimation(TranslateTransform.XProperty, null);
            progressTrack.Visibility = Visibility.Collapsed;
        }

        void ShowReady()
        {
            bool installed = File.Exists(Installer.HelperPath);
            busy = false;
            StopProgress();
            logBox.Visibility = Visibility.Collapsed;
            subtitle.Text = "Setup - version " + version;

            if (installed)
            {
                heading.Text = "Update Terminal Board";
                message.Text = "Terminal Board is already installed on this PC. This updates it and keeps your settings.";
                SetBullets();
                SetButtons("Update", StartInstall, "Cancel", Close);
            }
            else
            {
                heading.Text = "Ready to install";
                message.Text = "Terminal Board splits Windows Terminal into a workspace where Claude, Codex and other agents work side by side. It installs for your Windows account only, so no administrator rights are needed.";
                SetBullets(
                    "A Terminal Board icon on your Desktop and in the Start Menu",
                    "The tb command in every terminal",
                    "A small tray helper: Win+Shift+S, then Ctrl+V pastes a screenshot to an agent");
                SetButtons("Install", StartInstall, "Cancel", Close);
            }
        }

        void ShowInstalling(bool update)
        {
            busy = true;
            logBox.Visibility = Visibility.Collapsed;
            heading.Text = update ? "Updating..." : "Installing...";
            message.Text = "Setting everything up. This takes about half a minute.";
            SetBullets();
            SetButtons(null, null, null, null);
            StartProgress();
        }

        void ShowDone()
        {
            busy = false;
            StopProgress();
            logBox.Visibility = Visibility.Collapsed;
            heading.Text = "Terminal Board is ready";
            message.Text = "Click the Terminal Board icon on your Desktop to choose your panes and agents, then open your workspace.";
            SetBullets(
                "Desktop and Start Menu: Terminal Board",
                "Any terminal: type tb 5 to split it into 5 panes",
                "Screenshots: Win+Shift+S, then Ctrl+V in a terminal");
            SetButtons("Open Terminal Board", delegate { Installer.OpenTerminalBoard(); Close(); }, "Close", Close);
        }

        void ShowNeedsWindowsTerminal()
        {
            busy = false;
            StopProgress();
            logBox.Visibility = Visibility.Collapsed;
            heading.Text = "Windows Terminal is required";
            message.Text = "Terminal Board works inside Windows Terminal, which was not found on this PC. Install it from the Microsoft Store (it is free), then run this setup again.";
            SetBullets();
            SetButtons("Open Microsoft Store", Installer.OpenStore, "Close", Close);
        }

        void ShowFailed(string summary, string log)
        {
            busy = false;
            StopProgress();
            heading.Text = "Setup could not finish";
            message.Text = summary + " The details below may help.";
            SetBullets();
            logBox.Text = Tail(log, 40);
            logBox.Visibility = Visibility.Visible;
            logBox.ScrollToEnd();
            SetButtons("Try again", ShowReady, "Close", Close);
        }

        static string Tail(string text, int lines)
        {
            string[] all = (text ?? string.Empty).Replace("\r\n", "\n").Split('\n');
            if (all.Length <= lines)
            {
                return string.Join("\r\n", all);
            }
            return string.Join("\r\n", all.Skip(all.Length - lines).ToArray());
        }

        void Close()
        {
            busy = false;
            window.Close();
        }

        // ---- installing ----

        void StartInstall()
        {
            ShowInstalling(File.Exists(Installer.HelperPath));
            ThreadPool.QueueUserWorkItem(delegate
            {
                InstallResult result;
                try
                {
                    result = Installer.Run(version);
                }
                catch (Exception ex)
                {
                    result = new InstallResult();
                    result.Outcome = Outcome.Failed;
                    result.Summary = "Setup could not run: " + ex.Message;
                    result.Log = ex.ToString();
                }
                window.Dispatcher.BeginInvoke(new Action(delegate { ShowResult(result); }));
            });
        }

        void ShowResult(InstallResult result)
        {
            if (result.Outcome == Outcome.Success)
            {
                ShowDone();
            }
            else if (result.Outcome == Outcome.NeedsWindowsTerminal)
            {
                ShowNeedsWindowsTerminal();
            }
            else
            {
                ShowFailed(result.Summary, result.Log + "\r\nThe full log is saved to " + Installer.LogPath);
            }
        }

        // ---- a picture of the window (used by the tests) ----

        public bool SavePicture(string path)
        {
            // The window is as tall as its content, so measure with no height limit first.
            int width = (int)root.Width;
            root.Measure(new Size(width, double.PositiveInfinity));
            int height = (int)Math.Ceiling(root.DesiredSize.Height);
            root.Arrange(new Rect(0, 0, width, height));
            root.UpdateLayout();

            RenderTargetBitmap bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(root);
            PngBitmapEncoder encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (FileStream file = File.Create(path))
            {
                encoder.Save(file);
            }
            return File.Exists(path);
        }
    }

    // ---- entry point ----

    internal static class Program
    {
        static string Version()
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            object[] attributes = assembly.GetCustomAttributes(typeof(AssemblyInformationalVersionAttribute), false);
            if (attributes.Length > 0)
            {
                return ((AssemblyInformationalVersionAttribute)attributes[0]).InformationalVersion;
            }
            return assembly.GetName().Version.ToString();
        }

        [STAThread]
        static int Main(string[] args)
        {
            string extractTo = null;
            string snapshot = null;
            string snapshotState = "ready";
            bool silent = false;
            bool help = false;

            for (int i = 0; i < args.Length; i++)
            {
                string arg = args[i].ToLowerInvariant();
                if (arg == "/s" || arg == "-s" || arg == "/silent" || arg == "--silent")
                {
                    silent = true;
                }
                else if (arg == "/extract" && i + 1 < args.Length)
                {
                    extractTo = args[++i];
                }
                else if (arg == "/snapshot" && i + 1 < args.Length)
                {
                    snapshot = args[++i];
                    if (i + 1 < args.Length && !args[i + 1].StartsWith("/"))
                    {
                        snapshotState = args[++i];
                    }
                }
                else if (arg == "/?" || arg == "/help" || arg == "-h" || arg == "--help")
                {
                    help = true;
                }
            }

            try
            {
                if (help)
                {
                    MessageBox.Show(
                        "Terminal Board Setup\r\n\r\n" +
                        "TerminalBoardSetup.exe          install with a window\r\n" +
                        "TerminalBoardSetup.exe /S       install silently (exit code 0 = installed)\r\n" +
                        "TerminalBoardSetup.exe /extract <folder>   only unpack the install files\r\n\r\n" +
                        "The setup log is saved to " + Installer.LogPath,
                        "Terminal Board Setup", MessageBoxButton.OK, MessageBoxImage.Information);
                    return 0;
                }

                if (extractTo != null)
                {
                    Payload.ExtractTo(extractTo);
                    return 0;
                }

                if (snapshot != null)
                {
                    SetupWindow picture = new SetupWindow(Version());
                    picture.ShowState(snapshotState);
                    return picture.SavePicture(snapshot) ? 0 : 1;
                }

                if (silent)
                {
                    InstallResult result = Installer.Run(Version());
                    if (result.Outcome == Outcome.Success)
                    {
                        return 0;
                    }
                    return result.Outcome == Outcome.NeedsWindowsTerminal ? 3 : 1;
                }

                SetupWindow ui = new SetupWindow(Version());
                new Application().Run(ui.Window);
                return 0;
            }
            catch (Exception ex)
            {
                if (!silent)
                {
                    MessageBox.Show(ex.Message, "Terminal Board Setup", MessageBoxButton.OK, MessageBoxImage.Error);
                }
                return 1;
            }
        }
    }
}
