// Terminal Board settings screen (WPF) and the code that opens the board.
//
// The screen is compiled into TbClipboardHelper.exe so it opens without starting PowerShell.
// The first "--desk" starts a small server process that keeps the window ready; later clicks
// only signal it, so the screen appears almost at once. install.ps1 compiles this file with the
// csc.exe that ships with Windows, so keep it to C# 5 (no string interpolation, no "?.", no
// expression-bodied members).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace TerminalBoard
{
    internal sealed class AgentInfo
    {
        public readonly string Kind;
        public readonly string Name;        // short name on the screen
        public readonly string TitleName;   // name shown in the Windows Terminal tab
        public readonly string Command;     // null for "custom"
        public readonly string Color;

        public AgentInfo(string kind, string name, string titleName, string command, string color)
        {
            Kind = kind;
            Name = name;
            TitleName = titleName;
            Command = command;
            Color = color;
        }
    }

    internal static class Agents
    {
        public static readonly AgentInfo[] All = new AgentInfo[]
        {
            new AgentInfo("terminal", "Terminal", "Terminal", DeskStore.PlainShell, "#94A3B8"),
            new AgentInfo("claude", "Claude", "Claude Code", "claude", "#E58F65"),
            new AgentInfo("codex", "Codex", "Codex", "codex", "#6CA8FF"),
            new AgentInfo("agy", "Antigravity", "Antigravity", "agy", "#B79CFF"),
            new AgentInfo("custom", "Custom", "Custom", null, "#F2C15A")
        };

        public static AgentInfo ByKind(string kind)
        {
            foreach (AgentInfo agent in All)
            {
                if (agent.Kind == kind)
                {
                    return agent;
                }
            }
            return All[0];
        }

        public static AgentInfo ByCommand(string command)
        {
            foreach (AgentInfo agent in All)
            {
                if (agent.Command != null && string.Equals(agent.Command, command, StringComparison.OrdinalIgnoreCase))
                {
                    return agent;
                }
            }
            return null;
        }

        // Same rule as Get-TbPaneTitle in TerminalBoard.psm1.
        public static string Title(string command, int number)
        {
            if (string.IsNullOrEmpty(command))
            {
                return "TB " + number;
            }

            AgentInfo known = ByCommand(command);
            string name = known != null ? known.TitleName : (command.Length > 24 ? command.Substring(0, 24) : command);
            return number + " - " + name;
        }
    }

    internal sealed class DeskSettings
    {
        public string Folder;
        public int Count;
        public string Layout;
        public string[] Panes;
        public string Theme;
        public string Background;   // file name of the user's picture inside the data folder, or null
    }

    // A colour scheme for the settings screen. Every value is a hex colour.
    internal sealed class Theme
    {
        public string Key;
        public string Name;
        public string Bg1;          // window background, top-left
        public string Bg2;          // window background, bottom-right
        public string Card;
        public string Line;
        public string LineHover;
        public string Field;
        public string Field2;
        public string Hover;
        public string Text;
        public string Muted;
        public string ChipText;
        public string ChipOn;
        public string PreviewBg;
        public string PreviewBar;
        public string Accent1;      // accent gradient start
        public string Accent2;      // accent gradient end
        public string AccentSolid;
        public string OnAccent;     // text on the accent colour
        public string Selection;

        // Optional. Anything left out falls back to a sensible default in Complete().
        public string BgMid;        // middle stop of the window gradient
        public string HeaderLine;   // fine line under the header
        public string WinText;      // text that sits directly on the window background
        public string WinMuted;
        public string WinLine;
        public string WinHover;
        public string Ring;         // ring around the chosen colour dot
        public string ArtColor;     // the translucent artwork: rays and arcs
        public byte ArtAlpha;
        public string ArtAlt;       // optional second ray colour (light rays between the dark ones)
        public byte ArtAltAlpha;
        public string GlowColor;    // soft glow in the top-left corner
        public byte GlowAlpha;

        public void Complete()
        {
            if (HeaderLine == null) { HeaderLine = AccentSolid; }
            if (WinText == null) { WinText = Text; }
            if (WinMuted == null) { WinMuted = Muted; }
            if (WinLine == null) { WinLine = Line; }
            if (WinHover == null) { WinHover = Hover; }
            if (Ring == null) { Ring = AccentSolid; }
            if (ArtColor == null) { ArtColor = AccentSolid; }
            if (ArtAlpha == 0) { ArtAlpha = 16; }
            if (GlowColor == null) { GlowColor = AccentSolid; }
            if (GlowAlpha == 0) { GlowAlpha = 34; }
        }
    }

    internal static class Themes
    {
        public const string DefaultKey = "gold";

        public static readonly Theme[] All = new Theme[]
        {
            new Theme
            {
                Key = "gold", Name = "Imperial Gold (royal gold, soft pattern)",
                Bg1 = "#F8E7A6", BgMid = "#E3B650", Bg2 = "#A8711A",
                Card = "#E62A1B08", Line = "#99FFD86B", LineHover = "#FFE29A",
                Field = "#F0140D03", Field2 = "#F03A2810", Hover = "#F04A3413",
                Text = "#FFF6DC", Muted = "#D8C48E", ChipText = "#EFE3BB", ChipOn = "#5B4213",
                PreviewBg = "#F00E0802", PreviewBar = "#F02A1B08",
                Accent1 = "#4F3411", Accent2 = "#1F1405", AccentSolid = "#FFD86B", OnAccent = "#FFD86B", Selection = "#C9973A",
                HeaderLine = "#6A4A10", WinText = "#2A1A04", WinMuted = "#6A4B12", WinLine = "#7A5A1E", WinHover = "#40FFFFFF",
                Ring = "#2A1A04",
                ArtColor = "#5A3D0E", ArtAlpha = 46, ArtAlt = "#FFFFFF", ArtAltAlpha = 58,
                GlowColor = "#FFFFFF", GlowAlpha = 120
            },
            new Theme
            {
                Key = "midnight", Name = "Midnight Gold (navy blue, champagne gold)",
                Bg1 = "#141E4A", Bg2 = "#090E28", Card = "#E8182356", Line = "#2C3B78", LineHover = "#43549A",
                Field = "#0E1638", Field2 = "#1B2760", Hover = "#1F2C68", Text = "#F6F1E4", Muted = "#9BA6D0",
                ChipText = "#C9D0EC", ChipOn = "#232F70", PreviewBg = "#070B20", PreviewBar = "#0F1638",
                Accent1 = "#F6DE97", Accent2 = "#C9973A", AccentSolid = "#E7C670", OnAccent = "#1D1503", Selection = "#B98B2E"
            },
            new Theme
            {
                Key = "emerald", Name = "Emerald Gold (emerald green, gold)",
                Bg1 = "#0C3F37", Bg2 = "#04211B", Card = "#E8105048", Line = "#1F6E60", LineHover = "#33907F",
                Field = "#072F29", Field2 = "#14584D", Hover = "#166055", Text = "#F4EFE0", Muted = "#8FC7B8",
                ChipText = "#C6E3DA", ChipOn = "#1A6B5C", PreviewBg = "#041D18", PreviewBar = "#0A3A32",
                Accent1 = "#F3DA8E", Accent2 = "#C7963A", AccentSolid = "#E5C36E", OnAccent = "#1B1402", Selection = "#B98B2E"
            },
            new Theme
            {
                Key = "burgundy", Name = "Royal Burgundy (wine red, rose gold)",
                Bg1 = "#4C1230", Bg2 = "#1F0814", Card = "#E85A1A38", Line = "#7F2E52", LineHover = "#A34670",
                Field = "#360D20", Field2 = "#6B2444", Hover = "#722A4B", Text = "#FCEFE8", Muted = "#D6A8B8",
                ChipText = "#EFCFDA", ChipOn = "#7E2D52", PreviewBg = "#250A16", PreviewBar = "#3F1227",
                Accent1 = "#FADAB9", Accent2 = "#D9946B", AccentSolid = "#EEB78E", OnAccent = "#2B1107", Selection = "#C77F58"
            }
        };

        static Themes()
        {
            foreach (Theme theme in All)
            {
                theme.Complete();
            }
        }

        public static Theme Find(string key)
        {
            foreach (Theme theme in All)
            {
                if (theme.Key == key)
                {
                    return theme;
                }
            }
            return null;
        }
    }

    // Reads and writes desk.json, the same file `tb desk` uses.
    internal static class DeskStore
    {
        public const int MaxPanes = 12;
        public const string PlainShell = "@shell";

        public static string PathFor(string dataDirectory)
        {
            return Path.Combine(dataDirectory, "desk.json");
        }

        public static DeskSettings Defaults()
        {
            DeskSettings settings = new DeskSettings();
            settings.Folder = Environment.GetEnvironmentVariable("USERPROFILE");
            settings.Count = 5;
            settings.Layout = "columns";
            settings.Theme = Themes.DefaultKey;
            settings.Panes = new string[MaxPanes];
            for (int i = 0; i < MaxPanes; i++)
            {
                settings.Panes[i] = PlainShell;
            }
            return settings;
        }

        public static DeskSettings Load(string dataDirectory)
        {
            return LoadFile(PathFor(dataDirectory));
        }

        public static DeskSettings LoadFile(string path)
        {
            DeskSettings settings = Defaults();
            if (!File.Exists(path))
            {
                return settings;
            }

            try
            {
                JavaScriptSerializer json = new JavaScriptSerializer();
                Dictionary<string, object> saved = json.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
                if (saved == null)
                {
                    return settings;
                }

                object value;
                if (saved.TryGetValue("folder", out value) && value is string && Directory.Exists((string)value))
                {
                    settings.Folder = (string)value;
                }

                int count;
                if (saved.TryGetValue("count", out value) && value != null
                    && int.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), NumberStyles.Integer, CultureInfo.InvariantCulture, out count)
                    && count >= 1 && count <= MaxPanes)
                {
                    settings.Count = count;
                }

                if (saved.TryGetValue("layout", out value) && (Convert.ToString(value) == "columns" || Convert.ToString(value) == "rows"))
                {
                    settings.Layout = Convert.ToString(value);
                }

                if (saved.TryGetValue("theme", out value) && Themes.Find(Convert.ToString(value)) != null)
                {
                    settings.Theme = Convert.ToString(value);
                }

                // Only a plain file name is accepted, never a path.
                if (saved.TryGetValue("background", out value) && value is string && (string)value != string.Empty && Path.GetFileName((string)value) == (string)value)
                {
                    settings.Background = (string)value;
                }

                IEnumerable panes = saved.TryGetValue("panes", out value) ? value as IEnumerable : null;
                if (panes != null && !(value is string))
                {
                    int index = 0;
                    foreach (object pane in panes)
                    {
                        string command = Convert.ToString(pane);
                        if (index < MaxPanes && !string.IsNullOrEmpty(command))
                        {
                            settings.Panes[index] = command;
                        }
                        index++;
                    }
                }
            }
            catch (Exception)
            {
                // A damaged settings file should never stop the screen from opening.
            }

            return settings;
        }

        public static void Save(string dataDirectory, DeskSettings settings)
        {
            Directory.CreateDirectory(dataDirectory);
            Dictionary<string, object> data = new Dictionary<string, object>();
            data["folder"] = settings.Folder;
            data["count"] = settings.Count;
            data["layout"] = settings.Layout;
            data["theme"] = settings.Theme;
            if (!string.IsNullOrEmpty(settings.Background))
            {
                data["background"] = settings.Background;
            }
            data["panes"] = settings.Panes;
            // UTF-8 with a BOM so Windows PowerShell (which `tb desk` uses) reads non-ASCII folder names.
            File.WriteAllText(PathFor(dataDirectory), new JavaScriptSerializer().Serialize(data), new UTF8Encoding(true));
        }
    }

    // Builds and runs the Windows Terminal commands that open the board. It mirrors
    // Open-TbDesk in TerminalBoard.psm1; the tests compare the two.
    internal static class BoardLauncher
    {
        static string ShellExe()
        {
            string path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
            foreach (string directory in path.Split(';'))
            {
                if (directory.Trim().Length == 0)
                {
                    continue;
                }

                try
                {
                    string candidate = Path.Combine(directory.Trim(), "pwsh.exe");
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
                catch (ArgumentException)
                {
                }
            }

            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        }

        static void AddShell(List<string> tokens, string command)
        {
            if (string.IsNullOrEmpty(command))
            {
                command = DeskStore.PlainShell;
            }

            tokens.Add("--");
            tokens.Add(ShellExe());
            tokens.Add("-NoExit");
            if (command != DeskStore.PlainShell)
            {
                // Windows Terminal reads ';' as its own separator even inside a quoted argument.
                tokens.Add("-Command");
                tokens.Add(command.Replace(";", "\\;"));
            }
        }

        // Every pane after the first carves its share out of what is left, so all panes end up equal.
        static string SplitSize(int count, int paneNumber)
        {
            int remaining = count - paneNumber + 2;
            return ((remaining - 1) / (double)remaining).ToString("0.######", CultureInfo.InvariantCulture);
        }

        static void AddFirstPane(List<string> tokens, DeskSettings settings, string windowName)
        {
            tokens.AddRange(new string[] { "-w", windowName, "-M", "new-tab", "-d", settings.Folder, "--title", Agents.Title(settings.Panes[0], 1), "--suppressApplicationTitle" });
            AddShell(tokens, settings.Panes[0]);
        }

        static void AddSplit(List<string> tokens, DeskSettings settings, int paneNumber)
        {
            string orientation = settings.Layout == "rows" ? "-H" : "-V";
            tokens.AddRange(new string[] { "split-pane", orientation, "-s", SplitSize(settings.Count, paneNumber), "-d", settings.Folder, "--title", Agents.Title(settings.Panes[paneNumber - 1], paneNumber), "--suppressApplicationTitle" });
            AddShell(tokens, settings.Panes[paneNumber - 1]);
        }

        // The command in the same one-line form as `tb desk --dry-run`.
        public static string Preview(DeskSettings settings)
        {
            List<string> tokens = new List<string>();
            AddFirstPane(tokens, settings, "new");
            for (int pane = 2; pane <= settings.Count; pane++)
            {
                tokens.Add(";");
                AddSplit(tokens, settings, pane);
            }
            if (settings.Count > 1)
            {
                tokens.AddRange(new string[] { ";", "move-focus", "first" });
            }

            StringBuilder line = new StringBuilder("wt.exe");
            foreach (string token in tokens)
            {
                line.Append(' ').Append(FormatForPreview(token));
            }
            return line.ToString();
        }

        static string FormatForPreview(string argument)
        {
            if (argument == ";")
            {
                return ";";
            }

            foreach (char c in argument)
            {
                if (char.IsWhiteSpace(c) || c == '"')
                {
                    return "\"" + argument.Replace("\"", "\\\"") + "\"";
                }
            }
            return argument;
        }

        static string Quote(string argument)
        {
            if (argument.Length > 0 && argument.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0)
            {
                return argument;
            }

            StringBuilder quoted = new StringBuilder("\"");
            int backslashes = 0;
            foreach (char c in argument)
            {
                if (c == '\\')
                {
                    backslashes++;
                }
                else if (c == '"')
                {
                    quoted.Append('\\', backslashes * 2 + 1).Append('"');
                    backslashes = 0;
                }
                else
                {
                    quoted.Append('\\', backslashes).Append(c);
                    backslashes = 0;
                }
            }
            quoted.Append('\\', backslashes * 2).Append('"');
            return quoted.ToString();
        }

        static void Run(string[] arguments)
        {
            StringBuilder commandLine = new StringBuilder();
            foreach (string argument in arguments)
            {
                if (commandLine.Length > 0)
                {
                    commandLine.Append(' ');
                }
                commandLine.Append(Quote(argument));
            }

            ProcessStartInfo info = new ProcessStartInfo("wt.exe", commandLine.ToString());
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            try
            {
                using (Process process = Process.Start(info))
                {
                    process.WaitForExit(15000);
                }
            }
            catch (System.ComponentModel.Win32Exception)
            {
                throw new InvalidOperationException("Windows Terminal (wt.exe) was not found. Install Windows Terminal first.");
            }
        }

        public static void Open(DeskSettings settings)
        {
            if (!Directory.Exists(settings.Folder))
            {
                throw new InvalidOperationException("Working folder not found: " + settings.Folder);
            }

            // One wt.exe call that carries every step (new tab, splits, focus). Windows Terminal runs them in order
            // inside the new window. Separate calls can overtake the window's first tab and land in a second tab.
            List<string> tokens = new List<string>();
            AddFirstPane(tokens, settings, "new");
            for (int pane = 2; pane <= settings.Count; pane++)
            {
                tokens.Add(";");
                AddSplit(tokens, settings, pane);
            }
            if (settings.Count > 1)
            {
                tokens.AddRange(new string[] { ";", "move-focus", "first" });
            }
            Run(tokens.ToArray());
        }
    }

    internal sealed class Preset
    {
        public readonly string Name;
        public readonly string Detail;
        public readonly string[] Kinds;

        public Preset(string name, string detail, string[] kinds)
        {
            Name = name;
            Detail = detail;
            Kinds = kinds;
        }
    }

    internal sealed class DeskWindow
    {
        const string DefaultStatus = "Opens maximized, taskbar still visible. Screenshots: Win+Shift+S, then Ctrl+V.";

        static readonly Preset[] Presets = new Preset[]
        {
            new Preset("Terminals only", "5 working panes", new string[] { "terminal", "terminal", "terminal", "terminal", "terminal" }),
            new Preset("Claude + Codex", "2 panes, side by side", new string[] { "claude", "codex" }),
            new Preset("AI trio", "Claude, Codex, Antigravity", new string[] { "claude", "codex", "agy" }),
            new Preset("Parallel work", "6 panes: 2 Claude, 2 Codex, 1 Antigravity, 1 Terminal", new string[] { "claude", "claude", "codex", "codex", "agy", "terminal" })
        };

        sealed class RowUi
        {
            public Grid Line;
            public TextBox Custom;
            public List<RadioButton> Chips = new List<RadioButton>();
            public List<string> ChipKinds = new List<string>();
        }

        readonly string dataDirectory;
        readonly Window window;
        readonly TextBox txtFolder;
        readonly TextBlock txtCount;
        readonly TextBlock previewInfo;
        readonly TextBlock statusText;
        readonly Button btnMinus;
        readonly Button btnPlus;
        readonly Button btnSave;
        readonly Button btnOpen;
        readonly RadioButton chipCols;
        readonly RadioButton chipRows;
        readonly Panel rowsHost;
        readonly Panel presetsHost;
        readonly UniformGrid previewGrid;
        readonly Panel themeHost;
        readonly System.Windows.Shapes.Rectangle bgImage;
        readonly Button btnImage;
        string backgroundFile;
        readonly List<RowUi> rows = new List<RowUi>();
        readonly Dictionary<string, Button> swatches = new Dictionary<string, Button>();
        string themeKey = Themes.DefaultKey;
        readonly string[] kinds = new string[DeskStore.MaxPanes];
        readonly string[] customs = new string[DeskStore.MaxPanes];
        int count = 5;
        string layout = "columns";
        bool syncing;
        bool allowClose;

        // When true, closing the window only hides it so the next open is instant.
        public bool HideInsteadOfClose;

        public DeskWindow(string dataDirectory)
        {
            this.dataDirectory = dataDirectory;

            using (Stream stream = typeof(DeskWindow).Assembly.GetManifestResourceStream("TbDesk.xaml"))
            {
                window = (Window)XamlReader.Load(stream);
            }

            string location = typeof(DeskWindow).Assembly.Location;
            if (!string.IsNullOrEmpty(location))
            {
                string icon = Path.Combine(Path.GetDirectoryName(location), "TerminalBoard.ico");
                if (File.Exists(icon))
                {
                    try
                    {
                        // OnLoad reads the file now and lets go of it; otherwise the icon stays locked and a reinstall cannot replace it.
                        window.Icon = BitmapFrame.Create(new Uri(icon), BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                    }
                    catch (Exception)
                    {
                    }
                }
            }

            txtFolder = (TextBox)window.FindName("TxtFolder");
            txtCount = (TextBlock)window.FindName("TxtCount");
            previewInfo = (TextBlock)window.FindName("PreviewInfo");
            statusText = (TextBlock)window.FindName("StatusText");
            btnMinus = (Button)window.FindName("BtnMinus");
            btnPlus = (Button)window.FindName("BtnPlus");
            btnSave = (Button)window.FindName("BtnSave");
            btnOpen = (Button)window.FindName("BtnOpen");
            chipCols = (RadioButton)window.FindName("ChipCols");
            chipRows = (RadioButton)window.FindName("ChipRows");
            rowsHost = (Panel)window.FindName("RowsHost");
            presetsHost = (Panel)window.FindName("PresetsHost");
            previewGrid = (UniformGrid)window.FindName("PreviewGrid");
            themeHost = (Panel)window.FindName("ThemeHost");
            bgImage = (System.Windows.Shapes.Rectangle)window.FindName("BgImage");
            btnImage = (Button)window.FindName("BtnImage");

            LoadState();
            BuildRows();
            BuildPresets();
            Wire();
            BuildThemeSwatches();
            ApplyBackground();   // also applies the theme
            SyncChips();
            Refresh();
            SetStatus(DefaultStatus, false);
        }

        public bool IsVisible
        {
            get { return window.IsVisible; }
        }

        static SolidColorBrush MakeBrush(string hex, byte alpha)
        {
            Color color = (Color)ColorConverter.ConvertFromString(hex);
            SolidColorBrush brush = new SolidColorBrush(Color.FromArgb(alpha, color.R, color.G, color.B));
            brush.Freeze();
            return brush;
        }

        void LoadState()
        {
            DeskSettings settings = DeskStore.Load(dataDirectory);
            txtFolder.Text = settings.Folder;
            count = settings.Count;
            layout = settings.Layout;
            themeKey = settings.Theme;
            backgroundFile = settings.Background;
            for (int i = 0; i < DeskStore.MaxPanes; i++)
            {
                AgentInfo known = Agents.ByCommand(settings.Panes[i]);
                if (known != null)
                {
                    kinds[i] = known.Kind;
                    customs[i] = string.Empty;
                }
                else
                {
                    kinds[i] = "custom";
                    customs[i] = settings.Panes[i];
                }
            }
        }

        void BuildRows()
        {
            for (int i = 0; i < DeskStore.MaxPanes; i++)
            {
                int index = i;
                RowUi row = new RowUi();

                // A grid (number | choices) so the choices get a bounded width and wrap instead of being cut off.
                row.Line = new Grid();
                row.Line.Margin = new Thickness(0, 0, 0, 10);
                row.Line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.Line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                Border badge = new Border();
                badge.Width = 30;
                badge.Height = 30;
                badge.CornerRadius = new CornerRadius(15);
                badge.SetResourceReference(Border.BackgroundProperty, "Field2");
                badge.VerticalAlignment = VerticalAlignment.Top;
                badge.Margin = new Thickness(0, 1, 12, 0);
                TextBlock badgeText = new TextBlock();
                badgeText.Text = (i + 1).ToString(CultureInfo.InvariantCulture);
                badgeText.FontWeight = FontWeights.SemiBold;
                badgeText.SetResourceReference(TextBlock.ForegroundProperty, "ChipText");
                badgeText.HorizontalAlignment = HorizontalAlignment.Center;
                badgeText.VerticalAlignment = VerticalAlignment.Center;
                badge.Child = badgeText;

                StackPanel right = new StackPanel();
                WrapPanel chips = new WrapPanel();
                row.Custom = new TextBox();
                row.Custom.Style = (Style)window.FindResource("FieldBox");
                row.Custom.Height = 36;
                row.Custom.Margin = new Thickness(0, 0, 0, 4);
                row.Custom.VerticalContentAlignment = VerticalAlignment.Center;
                row.Custom.Visibility = Visibility.Collapsed;
                row.Custom.TextChanged += delegate
                {
                    customs[index] = row.Custom.Text;
                    UpdatePreview();
                };

                foreach (AgentInfo agent in Agents.All)
                {
                    AgentInfo captured = agent;
                    RadioButton chip = new RadioButton();
                    chip.Style = (Style)window.FindResource("Chip");
                    chip.Content = agent.Name;
                    chip.Tag = agent.Color;
                    chip.GroupName = "pane" + i;
                    chip.Checked += delegate
                    {
                        if (syncing)
                        {
                            return;
                        }
                        kinds[index] = captured.Kind;
                        Refresh();
                    };
                    chips.Children.Add(chip);
                    row.Chips.Add(chip);
                    row.ChipKinds.Add(agent.Kind);
                }

                right.Children.Add(chips);
                right.Children.Add(row.Custom);
                Grid.SetColumn(right, 1);
                row.Line.Children.Add(badge);
                row.Line.Children.Add(right);
                rowsHost.Children.Add(row.Line);
                rows.Add(row);
            }
        }

        void BuildPresets()
        {
            foreach (Preset preset in Presets)
            {
                Preset chosen = preset;
                Button button = new Button();
                button.Style = (Style)window.FindResource("CardButton");
                button.Width = 184;
                button.Margin = new Thickness(0, 0, 10, 10);
                button.HorizontalContentAlignment = HorizontalAlignment.Left;
                // The visible content is two lines of text, so name the button for screen readers and automation.
                AutomationProperties.SetName(button, preset.Name + ": " + preset.Detail);

                StackPanel stack = new StackPanel();
                TextBlock title = new TextBlock();
                title.Text = preset.Name;
                title.FontWeight = FontWeights.SemiBold;
                title.SetResourceReference(TextBlock.ForegroundProperty, "Text");
                TextBlock detail = new TextBlock();
                detail.Text = preset.Detail;
                detail.FontSize = 11;
                detail.SetResourceReference(TextBlock.ForegroundProperty, "Muted");
                detail.TextWrapping = TextWrapping.Wrap;
                detail.Margin = new Thickness(0, 2, 0, 0);
                stack.Children.Add(title);
                stack.Children.Add(detail);
                button.Content = stack;

                button.Click += delegate
                {
                    count = chosen.Kinds.Length;
                    for (int i = 0; i < chosen.Kinds.Length; i++)
                    {
                        kinds[i] = chosen.Kinds[i];
                        customs[i] = string.Empty;
                    }
                    SyncChips();
                    Refresh();
                    SetStatus("Preset applied: " + chosen.Name, false);
                };
                presetsHost.Children.Add(button);
            }
        }

        void Wire()
        {
            chipCols.IsChecked = layout != "rows";
            chipRows.IsChecked = layout == "rows";
            chipCols.Checked += delegate { layout = "columns"; Refresh(); };
            chipRows.Checked += delegate { layout = "rows"; Refresh(); };

            btnMinus.Click += delegate
            {
                if (count > 1)
                {
                    count--;
                    Refresh();
                }
            };
            btnPlus.Click += delegate
            {
                if (count < DeskStore.MaxPanes)
                {
                    count++;
                    Refresh();
                }
            };

            ((Button)window.FindName("BtnBrowse")).Click += delegate { Browse(); };
            btnSave.Click += delegate { Save(); };
            btnImage.Click += delegate { ChooseBackground(); };
            btnImage.MouseRightButtonUp += delegate { ClearBackground(); };
            btnOpen.Click += delegate { OpenBoard(); };
            ((Button)window.FindName("BtnClose")).Click += delegate { CloseOrHide(); };
            ((Button)window.FindName("BtnMin")).Click += delegate { window.WindowState = WindowState.Minimized; };

            ((FrameworkElement)window.FindName("Header")).MouseLeftButtonDown += delegate
            {
                try
                {
                    window.DragMove();
                }
                catch (InvalidOperationException)
                {
                }
            };

            window.KeyDown += delegate(object sender, KeyEventArgs e)
            {
                if (e.Key == Key.Escape)
                {
                    CloseOrHide();
                }
            };

            window.Closing += delegate(object sender, System.ComponentModel.CancelEventArgs e)
            {
                if (HideInsteadOfClose && !allowClose)
                {
                    e.Cancel = true;
                    window.Hide();
                }
            };
        }

        void SyncChips()
        {
            syncing = true;
            try
            {
                for (int i = 0; i < DeskStore.MaxPanes; i++)
                {
                    for (int c = 0; c < rows[i].Chips.Count; c++)
                    {
                        rows[i].Chips[c].IsChecked = rows[i].ChipKinds[c] == kinds[i];
                    }
                    rows[i].Custom.Text = customs[i];
                }
                chipCols.IsChecked = layout != "rows";
                chipRows.IsChecked = layout == "rows";
            }
            finally
            {
                syncing = false;
            }
        }

        void Refresh()
        {
            txtCount.Text = count.ToString(CultureInfo.InvariantCulture);
            for (int i = 0; i < DeskStore.MaxPanes; i++)
            {
                rows[i].Line.Visibility = i < count ? Visibility.Visible : Visibility.Collapsed;
                rows[i].Custom.Visibility = kinds[i] == "custom" ? Visibility.Visible : Visibility.Collapsed;
            }
            btnMinus.IsEnabled = count > 1;
            btnPlus.IsEnabled = count < DeskStore.MaxPanes;
            btnMinus.Opacity = btnMinus.IsEnabled ? 1 : 0.4;
            btnPlus.Opacity = btnPlus.IsEnabled ? 1 : 0.4;
            UpdatePreview();
        }

        void UpdatePreview()
        {
            previewGrid.Children.Clear();
            if (layout == "rows")
            {
                previewGrid.Columns = 1;
                previewGrid.Rows = count;
            }
            else
            {
                previewGrid.Rows = 1;
                previewGrid.Columns = count;
            }

            for (int i = 0; i < count; i++)
            {
                AgentInfo agent = Agents.ByKind(kinds[i]);
                string label = agent.Name;
                if (kinds[i] == "custom")
                {
                    string typed = (customs[i] ?? string.Empty).Trim();
                    label = typed.Length > 0 ? typed : "Custom";
                }

                Border tile = new Border();
                tile.Margin = new Thickness(3);
                tile.CornerRadius = new CornerRadius(7);
                tile.BorderThickness = new Thickness(1);
                tile.Background = MakeBrush(agent.Color, 34);
                tile.BorderBrush = MakeBrush(agent.Color, 190);

                StackPanel content = new StackPanel();
                content.VerticalAlignment = VerticalAlignment.Center;
                content.HorizontalAlignment = HorizontalAlignment.Center;
                TextBlock number = new TextBlock();
                number.Text = (i + 1).ToString(CultureInfo.InvariantCulture);
                number.FontSize = 11;
                number.HorizontalAlignment = HorizontalAlignment.Center;
                number.SetResourceReference(TextBlock.ForegroundProperty, "Muted");
                TextBlock name = new TextBlock();
                name.Text = label;
                name.FontSize = count > 6 ? 10 : 12;
                name.FontWeight = FontWeights.SemiBold;
                name.HorizontalAlignment = HorizontalAlignment.Center;
                name.TextTrimming = TextTrimming.CharacterEllipsis;
                name.MaxWidth = 90;
                name.Foreground = MakeBrush(agent.Color, 255);
                content.Children.Add(number);
                content.Children.Add(name);
                tile.Child = content;
                previewGrid.Children.Add(tile);
            }

            previewInfo.Text = count + (count == 1 ? " pane" : " panes") + " · " + (layout == "rows" ? "stacked" : "side by side");
        }

        void SetStatus(string text, bool isError)
        {
            statusText.Text = text;
            if (isError)
            {
                statusText.Foreground = MakeBrush("#FF8A8A", 255);
            }
            else
            {
                statusText.SetResourceReference(TextBlock.ForegroundProperty, "WinMuted");
            }
        }

        // ---- colour themes ----

        void BuildThemeSwatches()
        {
            foreach (Theme theme in Themes.All)
            {
                Theme chosen = theme;
                Button swatch = new Button();
                swatch.Style = (Style)window.FindResource("Swatch");
                swatch.ToolTip = theme.Name;
                AutomationProperties.SetName(swatch, "Theme " + theme.Name);

                LinearGradientBrush fill = new LinearGradientBrush();
                fill.StartPoint = new Point(0, 0);
                fill.EndPoint = new Point(1, 1);
                fill.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(theme.Bg1), 0.0));
                fill.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(theme.BgMid ?? theme.Card), 0.5));
                fill.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(theme.AccentSolid), 1.0));
                swatch.Background = fill;

                swatch.Click += delegate
                {
                    ApplyTheme(chosen.Key);
                    PersistAppearance();
                };
                themeHost.Children.Add(swatch);
                swatches[theme.Key] = swatch;
            }
        }

        static SolidColorBrush Solid(string hex)
        {
            // #AARRGGBB is honoured, so a theme can make its cards translucent.
            SolidColorBrush brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            brush.Freeze();
            return brush;
        }

        static LinearGradientBrush Gradient(string from, string to, Point start, Point end)
        {
            LinearGradientBrush brush = new LinearGradientBrush();
            brush.StartPoint = start;
            brush.EndPoint = end;
            brush.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(from), 0.0));
            brush.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(to), 1.0));
            brush.Freeze();
            return brush;
        }

        void ApplyTheme(string key)
        {
            Theme theme = Themes.Find(key) ?? Themes.Find(Themes.DefaultKey);
            themeKey = theme.Key;

            // Every colour in the layout is a DynamicResource, so replacing the resource recolours the whole screen.
            window.Resources["WindowBg"] = theme.BgMid != null
                ? Gradient3(theme.Bg1, theme.BgMid, theme.Bg2, new Point(0, 0), new Point(1, 1))
                : Gradient(theme.Bg1, theme.Bg2, new Point(0, 0), new Point(1, 1));
            window.Resources["AccentBrush"] = Gradient(theme.Accent1, theme.Accent2, new Point(0, 0), new Point(1, 1));
            // With a picture behind, make the cards a little more transparent so the picture shows through.
            window.Resources["Card"] = string.IsNullOrEmpty(backgroundFile) ? Solid(theme.Card) : Scaled(theme.Card, 0.8);
            window.Resources["Line"] = Solid(theme.Line);
            window.Resources["LineHover"] = Solid(theme.LineHover);
            window.Resources["Field"] = Solid(theme.Field);
            window.Resources["Field2"] = Solid(theme.Field2);
            window.Resources["Hover"] = Solid(theme.Hover);
            window.Resources["Text"] = Solid(theme.Text);
            window.Resources["Muted"] = Solid(theme.Muted);
            window.Resources["ChipText"] = Solid(theme.ChipText);
            window.Resources["ChipOn"] = Solid(theme.ChipOn);
            window.Resources["PreviewBg"] = Solid(theme.PreviewBg);
            window.Resources["PreviewBar"] = Solid(theme.PreviewBar);
            window.Resources["AccentSolid"] = Solid(theme.AccentSolid);
            window.Resources["OnAccent"] = Solid(theme.OnAccent);
            window.Resources["Selection"] = Solid(theme.Selection);
            window.Resources["WinText"] = Solid(theme.WinText);
            window.Resources["WinMuted"] = Solid(theme.WinMuted);
            window.Resources["WinLine"] = Solid(theme.WinLine);
            window.Resources["WinHover"] = Solid(theme.WinHover);
            window.Resources["ArtBrush"] = BuildArt(theme);

            Color accent = (Color)ColorConverter.ConvertFromString(theme.HeaderLine);
            LinearGradientBrush line = new LinearGradientBrush();
            line.StartPoint = new Point(0, 0);
            line.EndPoint = new Point(1, 0);
            line.GradientStops.Add(new GradientStop(Color.FromArgb(0, accent.R, accent.G, accent.B), 0.0));
            line.GradientStops.Add(new GradientStop(Color.FromArgb(153, accent.R, accent.G, accent.B), 0.5));
            line.GradientStops.Add(new GradientStop(Color.FromArgb(0, accent.R, accent.G, accent.B), 1.0));
            line.Freeze();
            window.Resources["AccentLine"] = line;

            // The layout chips read their colour from Tag (a string), not from a resource.
            chipCols.Tag = theme.AccentSolid;
            chipRows.Tag = theme.AccentSolid;

            foreach (KeyValuePair<string, Button> entry in swatches)
            {
                entry.Value.BorderBrush = entry.Key == theme.Key ? Solid(theme.Ring) : Brushes.Transparent;
            }
        }

        // The same colour with its opacity multiplied (a card colour that is already translucent gets more so).
        static SolidColorBrush Scaled(string hex, double factor)
        {
            Color color = (Color)ColorConverter.ConvertFromString(hex);
            SolidColorBrush brush = new SolidColorBrush(Color.FromArgb((byte)(color.A * factor), color.R, color.G, color.B));
            brush.Freeze();
            return brush;
        }

        static LinearGradientBrush Gradient3(string from, string mid, string to, Point start, Point end)
        {
            LinearGradientBrush brush = new LinearGradientBrush();
            brush.StartPoint = start;
            brush.EndPoint = end;
            brush.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(from), 0.0));
            brush.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(mid), 0.5));
            brush.GradientStops.Add(new GradientStop((Color)ColorConverter.ConvertFromString(to), 1.0));
            brush.Freeze();
            return brush;
        }

        static Color WithAlpha(string hex, byte alpha)
        {
            Color color = (Color)ColorConverter.ConvertFromString(hex);
            return Color.FromArgb(alpha, color.R, color.G, color.B);
        }

        // The translucent artwork behind everything: a soft glow, an Art Deco sunburst fanning out from the
        // bottom-right corner, and fine concentric arcs. Drawn as vectors, so it stays sharp at any size.
        static Brush BuildArt(Theme theme)
        {
            const double Width = 1012;
            const double Height = 696;
            Rect bounds = new Rect(0, 0, Width, Height);
            DrawingGroup group = new DrawingGroup();
            group.ClipGeometry = new RectangleGeometry(bounds);

            RadialGradientBrush glow = new RadialGradientBrush();
            glow.Center = new Point(0.1, 0.05);
            glow.GradientOrigin = new Point(0.1, 0.05);
            glow.RadiusX = 0.75;
            glow.RadiusY = 1.0;
            glow.GradientStops.Add(new GradientStop(WithAlpha(theme.GlowColor, theme.GlowAlpha), 0.0));
            glow.GradientStops.Add(new GradientStop(WithAlpha(theme.GlowColor, 0), 1.0));
            group.Children.Add(new GeometryDrawing(glow, null, new RectangleGeometry(bounds)));

            Point origin = new Point(Width, Height);
            const double Radius = 1500;
            const int Wedges = 24;
            for (int i = 0; i < Wedges; i++)
            {
                bool dark = i % 2 == 0;
                if (!dark && theme.ArtAlt == null)
                {
                    continue;
                }

                double from = (180 + i * 90.0 / Wedges) * Math.PI / 180;
                double to = (180 + (i + 1) * 90.0 / Wedges) * Math.PI / 180;
                PathFigure figure = new PathFigure();
                figure.StartPoint = origin;
                figure.IsClosed = true;
                figure.Segments.Add(new LineSegment(new Point(origin.X + Radius * Math.Cos(from), origin.Y + Radius * Math.Sin(from)), true));
                figure.Segments.Add(new LineSegment(new Point(origin.X + Radius * Math.Cos(to), origin.Y + Radius * Math.Sin(to)), true));
                PathGeometry wedge = new PathGeometry();
                wedge.Figures.Add(figure);

                Color color = dark ? WithAlpha(theme.ArtColor, theme.ArtAlpha) : WithAlpha(theme.ArtAlt, theme.ArtAltAlpha);
                group.Children.Add(new GeometryDrawing(new SolidColorBrush(color), null, wedge));
            }

            Pen arc = new Pen(new SolidColorBrush(WithAlpha(theme.ArtColor, (byte)Math.Min(255, theme.ArtAlpha * 2))), 1.2);
            foreach (double radius in new double[] { 170, 290, 420, 560, 710 })
            {
                group.Children.Add(new GeometryDrawing(null, arc, new EllipseGeometry(origin, radius, radius)));
            }

            DrawingBrush brush = new DrawingBrush(group);
            brush.Stretch = Stretch.Fill;
            brush.Freeze();
            return brush;
        }

        // ---- the user's own background picture ----

        void ApplyBackground()
        {
            string path = string.IsNullOrEmpty(backgroundFile) ? null : Path.Combine(dataDirectory, backgroundFile);
            if (path == null || !File.Exists(path))
            {
                bgImage.Fill = null;
                backgroundFile = null;
                ApplyTheme(themeKey);
                return;
            }

            try
            {
                BitmapImage image = new BitmapImage();
                image.BeginInit();
                image.CacheOption = BitmapCacheOption.OnLoad;   // read it now, so the file is not locked
                image.DecodePixelWidth = 1400;
                image.UriSource = new Uri(path);
                image.EndInit();
                image.Freeze();
                ImageBrush brush = new ImageBrush(image);
                brush.Stretch = Stretch.UniformToFill;
                brush.Freeze();
                bgImage.Fill = brush;
                bgImage.Opacity = 0.42;
            }
            catch (Exception)
            {
                bgImage.Fill = null;
                backgroundFile = null;
            }
            ApplyTheme(themeKey);
        }

        void RemoveBackgroundFiles()
        {
            if (!Directory.Exists(dataDirectory))
            {
                return;
            }
            foreach (string file in Directory.GetFiles(dataDirectory, "background.*"))
            {
                try
                {
                    File.Delete(file);
                }
                catch (IOException)
                {
                }
            }
        }

        void ChooseBackground()
        {
            Microsoft.Win32.OpenFileDialog dialog = new Microsoft.Win32.OpenFileDialog();
            dialog.Title = "Choose a background picture";
            dialog.Filter = "Pictures (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp";
            if (dialog.ShowDialog(window) != true)
            {
                return;
            }

            try
            {
                Directory.CreateDirectory(dataDirectory);
                RemoveBackgroundFiles();
                string name = "background" + Path.GetExtension(dialog.FileName).ToLowerInvariant();
                File.Copy(dialog.FileName, Path.Combine(dataDirectory, name), true);
                backgroundFile = name;
                ApplyBackground();
                PersistAppearance();
                SetStatus("Background picture set. Right-click the picture button to remove it.", false);
            }
            catch (Exception ex)
            {
                SetStatus("Could not set the background picture: " + ex.Message, true);
            }
        }

        void ClearBackground()
        {
            try
            {
                RemoveBackgroundFiles();
            }
            catch (Exception)
            {
            }
            backgroundFile = null;
            ApplyBackground();
            PersistAppearance();
            SetStatus("Background picture removed.", false);
        }

        // Remembers the chosen colour theme and picture without touching the other settings.
        void PersistAppearance()
        {
            try
            {
                DeskSettings saved = DeskStore.Load(dataDirectory);
                saved.Theme = themeKey;
                saved.Background = backgroundFile;
                DeskStore.Save(dataDirectory, saved);
            }
            catch (Exception)
            {
                // Remembering the look is a nicety; never fail the screen over it.
            }
        }
        DeskSettings ReadScreen()
        {
            string folder = txtFolder.Text.Trim();
            if (!Directory.Exists(folder))
            {
                throw new InvalidOperationException("The working folder does not exist. Click \"Browse\" to choose another one.");
            }

            DeskSettings settings = new DeskSettings();
            settings.Folder = folder;
            settings.Count = count;
            settings.Layout = layout;
            settings.Theme = themeKey;
            settings.Background = backgroundFile;
            settings.Panes = new string[DeskStore.MaxPanes];
            for (int i = 0; i < DeskStore.MaxPanes; i++)
            {
                if (kinds[i] == "custom")
                {
                    string typed = (customs[i] ?? string.Empty).Trim();
                    if (i < count && typed.Length == 0)
                    {
                        throw new InvalidOperationException("Pane " + (i + 1) + ": type the command to run, or pick another agent.");
                    }
                    settings.Panes[i] = typed.Length > 0 ? typed : DeskStore.PlainShell;
                }
                else
                {
                    settings.Panes[i] = Agents.ByKind(kinds[i]).Command;
                }
            }
            return settings;
        }

        void Browse()
        {
            using (System.Windows.Forms.FolderBrowserDialog dialog = new System.Windows.Forms.FolderBrowserDialog())
            {
                dialog.Description = "Choose the working folder for the panes";
                if (Directory.Exists(txtFolder.Text))
                {
                    dialog.SelectedPath = txtFolder.Text;
                }
                if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                {
                    txtFolder.Text = dialog.SelectedPath;
                }
            }
        }

        void Save()
        {
            try
            {
                DeskStore.Save(dataDirectory, ReadScreen());
                SetStatus("Saved. These choices will be remembered next time.", false);
            }
            catch (Exception ex)
            {
                SetStatus(ex.Message, true);
            }
        }

        void OpenBoard()
        {
            DeskSettings settings;
            try
            {
                settings = ReadScreen();
                DeskStore.Save(dataDirectory, settings);
            }
            catch (Exception ex)
            {
                SetStatus(ex.Message, true);
                return;
            }

            SetStatus("Opening workspace...", false);
            btnOpen.IsEnabled = false;
            btnSave.IsEnabled = false;

            // Opening takes a moment (one Windows Terminal call per pane); keep the screen responsive meanwhile.
            ThreadPool.QueueUserWorkItem(delegate
            {
                string error = null;
                try
                {
                    BoardLauncher.Open(settings);
                }
                catch (Exception ex)
                {
                    error = ex.Message;
                }

                window.Dispatcher.BeginInvoke(new Action(delegate
                {
                    btnOpen.IsEnabled = true;
                    btnSave.IsEnabled = true;
                    if (error == null)
                    {
                        CloseOrHide();
                    }
                    else
                    {
                        SetStatus(error, true);
                    }
                }));
            });
        }

        void CloseOrHide()
        {
            if (HideInsteadOfClose && !allowClose)
            {
                window.Hide();
            }
            else
            {
                window.Close();
            }
        }

        public void ShowAndActivate()
        {
            // Show the saved choices again (unsaved edits from an earlier visit are dropped).
            LoadState();
            ApplyBackground();   // also applies the theme
            SyncChips();
            Refresh();
            SetStatus(DefaultStatus, false);
            btnOpen.IsEnabled = true;
            btnSave.IsEnabled = true;

            if (window.WindowState == WindowState.Minimized)
            {
                window.WindowState = WindowState.Normal;
            }
            window.Show();
            window.Topmost = true;
            window.Activate();
            window.Topmost = false;
        }

        // Draws the window once, invisibly and off-screen, so the first real show only has to make it visible.
        public void Prewarm()
        {
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.Left = -32000;
            window.Top = -32000;
            window.Opacity = 0;
            window.ShowInTaskbar = false;
            window.Show();
            window.Dispatcher.Invoke(new Action(delegate { }), DispatcherPriority.ApplicationIdle);
            window.Hide();

            window.Opacity = 1;
            window.ShowInTaskbar = true;
            Rect area = SystemParameters.WorkArea;
            window.Left = area.Left + (area.Width - window.Width) / 2;
            window.Top = area.Top + (area.Height - window.Height) / 2;
        }

        public void ForceClose()
        {
            allowClose = true;
            window.Close();
        }

        // Draws the screen off-screen into a PNG (used by the tests and for visual checks).
        public void SaveSnapshot(string pngPath)
        {
            window.WindowStartupLocation = WindowStartupLocation.Manual;
            window.Left = -4000;
            window.Top = -4000;
            window.ShowInTaskbar = false;
            window.Show();
            window.Dispatcher.Invoke(new Action(delegate { }), DispatcherPriority.ApplicationIdle);

            RenderTargetBitmap bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(window);
            PngBitmapEncoder encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using (FileStream stream = File.Create(pngPath))
            {
                encoder.Save(stream);
            }

            ForceClose();
        }
    }

    // Keeps the settings screen ready in a small background process, so opening it is instant after the first time.
    internal static class DeskServer
    {
        public const string ShowSignalName = "Local\\TerminalBoardShowDesk";
        public const string ExitSignalName = "Local\\TerminalBoardDeskExit";
        const string MutexName = "Local\\TerminalBoardDeskServer";
        static readonly TimeSpan IdleLimit = TimeSpan.FromHours(6);

        // Runs until asked to exit or idle for a long time. Called when no server is running yet.
        // With showNow false it only prepares the screen in the background (so the first real open is instant).
        public static int Run(string dataDirectory, bool showNow)
        {
            bool created;
            using (Mutex mutex = new Mutex(true, MutexName, out created))
            {
                if (!created)
                {
                    // Another server just started; ask it to show the screen if we were asked to.
                    EventWaitHandle existing;
                    if (EventWaitHandle.TryOpenExisting(ShowSignalName, out existing))
                    {
                        if (showNow)
                        {
                            existing.Set();
                        }
                        existing.Close();
                    }
                    return 0;
                }

                using (EventWaitHandle show = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSignalName))
                using (EventWaitHandle exit = new EventWaitHandle(false, EventResetMode.AutoReset, ExitSignalName))
                {
                    Application app = new Application();
                    app.ShutdownMode = ShutdownMode.OnExplicitShutdown;

                    DeskWindow desk = new DeskWindow(dataDirectory);
                    desk.HideInsteadOfClose = true;
                    DateTime lastSeen = DateTime.UtcNow;

                    DispatcherTimer timer = new DispatcherTimer();
                    timer.Interval = TimeSpan.FromMilliseconds(120);
                    timer.Tick += delegate
                    {
                        if (exit.WaitOne(0))
                        {
                            desk.ForceClose();
                            app.Shutdown();
                            return;
                        }
                        if (show.WaitOne(0))
                        {
                            desk.ShowAndActivate();
                        }
                        if (desk.IsVisible)
                        {
                            lastSeen = DateTime.UtcNow;
                        }
                        else if (DateTime.UtcNow - lastSeen > IdleLimit)
                        {
                            desk.ForceClose();
                            app.Shutdown();
                        }
                    };
                    timer.Start();

                    if (showNow)
                    {
                        desk.ShowAndActivate();
                    }
                    else
                    {
                        desk.Prewarm();
                    }
                    app.Run();
                    return 0;
                }
            }
        }

        public static int Snapshot(string dataDirectory, string pngPath)
        {
            Application app = new Application();
            app.ShutdownMode = ShutdownMode.OnExplicitShutdown;
            DeskWindow desk = new DeskWindow(dataDirectory);
            desk.SaveSnapshot(pngPath);
            return 0;
        }

        // Opens the saved board straight away, without showing the screen.
        public static int OpenSaved(string dataDirectory)
        {
            try
            {
                BoardLauncher.Open(DeskStore.Load(dataDirectory));
                return 0;
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Terminal Board", MessageBoxButton.OK, MessageBoxImage.Warning);
                return 1;
            }
        }

        // Writes the command that opening the saved settings file would run (used by the tests).
        public static int PrintBoard(string settingsPath, string outputPath)
        {
            File.WriteAllText(outputPath, BoardLauncher.Preview(DeskStore.LoadFile(settingsPath)), new UTF8Encoding(false));
            return 0;
        }
    }
}
