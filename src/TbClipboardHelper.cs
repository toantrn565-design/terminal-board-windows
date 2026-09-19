// Terminal Board clipboard helper.
//
// Runs in the background with a tray icon. When a plain picture lands on the
// clipboard (Win+Shift+S, PrintScreen, Paint...) it saves the picture as a PNG
// and replaces the clipboard with ONE package holding both the picture and the
// file path as text. Ctrl+V in a terminal then pastes the path (terminals only
// paste text), while Ctrl+V in Word, Paint or a chat app still pastes the picture.
//
// install.ps1 compiles this file with the csc.exe that ships with Windows, so
// keep it to C# 5 (no string interpolation, no "?.", no expression-bodied members).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace TerminalBoard
{
    public static class ImageStore
    {
        public const string FilePrefix = "img-";

        public static string Save(Image image, string directory)
        {
            Directory.CreateDirectory(directory);
            string name = FilePrefix + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + ".png";
            string path = Path.Combine(directory, name);
            image.Save(path, ImageFormat.Png);
            return path;
        }

        // Deletes pictures this helper saved that are older than maxAge. Other files are left alone.
        public static int Cleanup(string directory, TimeSpan maxAge)
        {
            if (!Directory.Exists(directory))
            {
                return 0;
            }

            int removed = 0;
            DateTime cutoff = DateTime.Now - maxAge;
            foreach (string file in Directory.GetFiles(directory, FilePrefix + "*.png"))
            {
                try
                {
                    if (File.GetLastWriteTime(file) < cutoff)
                    {
                        File.Delete(file);
                        removed++;
                    }
                }
                catch (IOException)
                {
                }
                catch (UnauthorizedAccessException)
                {
                }
            }
            return removed;
        }

        // A path with spaces is quoted so a shell or agent reads it as one argument. The
        // trailing space lets the user keep typing, or paste a second picture, right away.
        public static string ToClipboardText(string path)
        {
            string text = path.IndexOf(' ') >= 0 ? "\"" + path + "\"" : path;
            return text + " ";
        }
    }

    // Decides whether the clipboard holds a plain picture that is safe to re-publish.
    // Anything richer (text, files, HTML, Office objects, password-manager data) is left untouched.
    public static class ClipboardInspector
    {
        static readonly string[] PictureFormats = { "CF_BITMAP", "CF_DIB", "CF_DIBV5", "PNG" };

        static readonly string[] BlockingFormats =
        {
            "CF_TEXT", "CF_OEMTEXT", "CF_UNICODETEXT", "CF_HDROP", "CF_ENHMETAFILE", "CF_METAFILEPICT"
        };

        static readonly string[] BlockingMarkers =
        {
            "html format", "rich text format", "art::", "embed source", "link source",
            "object descriptor", "filegroupdescriptor", "photoshop", "adobe", "csv", "biff",
            "excludeclipboardcontentfrommonitorprocessing"
        };

        public static bool HasPicture(IEnumerable<string> formats)
        {
            foreach (string format in formats)
            {
                if (Array.IndexOf(PictureFormats, format) >= 0)
                {
                    return true;
                }
            }
            return false;
        }

        public static bool IsPlainPicture(IEnumerable<string> formats)
        {
            bool hasPicture = false;
            foreach (string format in formats)
            {
                if (Array.IndexOf(BlockingFormats, format) >= 0)
                {
                    return false;
                }

                string lower = format.ToLowerInvariant();
                foreach (string marker in BlockingMarkers)
                {
                    if (lower.IndexOf(marker, StringComparison.Ordinal) >= 0)
                    {
                        return false;
                    }
                }

                if (Array.IndexOf(PictureFormats, format) >= 0)
                {
                    hasPicture = true;
                }
            }
            return hasPicture;
        }

        // Names of every format currently on the clipboard, or null when another program keeps it open.
        public static List<string> ListFormats()
        {
            for (int attempt = 0; attempt < 10; attempt++)
            {
                if (Native.OpenClipboard(IntPtr.Zero))
                {
                    try
                    {
                        List<string> names = new List<string>();
                        uint format = 0;
                        while ((format = Native.EnumClipboardFormats(format)) != 0)
                        {
                            names.Add(FormatName(format));
                        }
                        return names;
                    }
                    finally
                    {
                        Native.CloseClipboard();
                    }
                }
                Thread.Sleep(20);
            }
            return null;
        }

        static string FormatName(uint format)
        {
            switch (format)
            {
                case 1: return "CF_TEXT";
                case 2: return "CF_BITMAP";
                case 3: return "CF_METAFILEPICT";
                case 7: return "CF_OEMTEXT";
                case 8: return "CF_DIB";
                case 13: return "CF_UNICODETEXT";
                case 14: return "CF_ENHMETAFILE";
                case 15: return "CF_HDROP";
                case 16: return "CF_LOCALE";
                case 17: return "CF_DIBV5";
            }

            StringBuilder name = new StringBuilder(128);
            return Native.GetClipboardFormatName(format, name, name.Capacity) > 0 ? name.ToString() : "#" + format;
        }
    }

    internal static class Native
    {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool OpenClipboard(IntPtr hWndNewOwner);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool CloseClipboard();

        [DllImport("user32.dll")]
        public static extern uint EnumClipboardFormats(uint format);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetClipboardFormatName(uint format, StringBuilder buffer, int maxCount);

        [DllImport("user32.dll")]
        public static extern uint GetClipboardSequenceNumber();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool AddClipboardFormatListener(IntPtr hwnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RemoveClipboardFormatListener(IntPtr hwnd);
    }

    // A message-only window that Windows notifies whenever the clipboard changes.
    internal sealed class ClipboardWindow : NativeWindow
    {
        const int WM_CLIPBOARDUPDATE = 0x031D;
        static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);

        public event EventHandler Updated;

        public ClipboardWindow()
        {
            CreateParams parameters = new CreateParams();
            parameters.Parent = HWND_MESSAGE;
            CreateHandle(parameters);

            if (!Native.AddClipboardFormatListener(Handle))
            {
                throw new InvalidOperationException("AddClipboardFormatListener failed");
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_CLIPBOARDUPDATE && Updated != null)
            {
                Updated(this, EventArgs.Empty);
            }
            base.WndProc(ref m);
        }

        public void Close()
        {
            Native.RemoveClipboardFormatListener(Handle);
            DestroyHandle();
        }
    }

    internal sealed class HelperContext : ApplicationContext
    {
        public const string ExitSignalName = "Local\\TerminalBoardClipboardHelperExit";

        static readonly TimeSpan KeepImages = TimeSpan.FromDays(30);

        readonly string dataDirectory;
        readonly string imageDirectory;
        readonly ClipboardWindow window;
        readonly System.Windows.Forms.Timer debounce = new System.Windows.Forms.Timer();
        readonly System.Windows.Forms.Timer exitPoll = new System.Windows.Forms.Timer();
        readonly EventWaitHandle exitSignal;
        readonly NotifyIcon tray = new NotifyIcon();
        readonly ToolStripMenuItem pauseItem;
        uint ownSequence;   // clipboard sequence number right after our own write
        int retries;
        bool paused;

        public HelperContext(string dataDirectory)
        {
            this.dataDirectory = dataDirectory;
            imageDirectory = Path.Combine(dataDirectory, "images");
            Directory.CreateDirectory(imageDirectory);

            int removed = ImageStore.Cleanup(imageDirectory, KeepImages);
            Log("started" + (removed > 0 ? ", removed " + removed + " old picture(s)" : ""));

            exitSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ExitSignalName);
            exitPoll.Interval = 500;
            exitPoll.Tick += delegate
            {
                if (exitSignal.WaitOne(0))
                {
                    ExitThread();
                }
            };
            exitPoll.Start();

            System.Windows.Forms.Timer warmTimer = new System.Windows.Forms.Timer();
            warmTimer.Interval = 10000;
            warmTimer.Tick += delegate
            {
                warmTimer.Stop();
                warmTimer.Dispose();
                WarmDesk();
            };
            warmTimer.Start();

            pauseItem = new ToolStripMenuItem("Pause");
            pauseItem.CheckOnClick = true;
            pauseItem.CheckedChanged += delegate
            {
                paused = pauseItem.Checked;
                SetTrayText(paused ? "Terminal Board: paused" : "Terminal Board: watching for screenshots");
                Log(paused ? "paused" : "resumed");
            };

            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem deskItem = new ToolStripMenuItem("Open Terminal Board", null, delegate { OpenDesk(); });
            deskItem.Font = new Font(deskItem.Font, FontStyle.Bold);
            menu.Items.Add(deskItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Open screenshots folder", null, delegate { OpenImageFolder(); }));
            menu.Items.Add(pauseItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(new ToolStripMenuItem("Exit", null, delegate { ExitThread(); }));

            tray.Icon = LoadIcon();
            tray.ContextMenuStrip = menu;
            tray.DoubleClick += delegate { OpenDesk(); };
            SetTrayText("Terminal Board: watching for screenshots");
            tray.Visible = true;

            debounce.Interval = 150;
            debounce.Tick += OnDebounceTick;

            window = new ClipboardWindow();
            window.Updated += delegate
            {
                // Clipboard updates often arrive in bursts; wait until it settles.
                retries = 0;
                debounce.Stop();
                debounce.Interval = 150;
                debounce.Start();
            };
        }

        void OnDebounceTick(object sender, EventArgs e)
        {
            debounce.Stop();
            if (paused)
            {
                return;
            }

            try
            {
                if (!HandleClipboard())
                {
                    ScheduleRetry();
                }
            }
            catch (ExternalException)
            {
                // Another program had the clipboard open at that moment.
                ScheduleRetry();
            }
            catch (Exception ex)
            {
                Log("error: " + ex.Message);
            }
        }

        void ScheduleRetry()
        {
            if (++retries > 5)
            {
                Log("clipboard stayed busy, gave up");
                return;
            }
            debounce.Interval = 120;
            debounce.Start();
        }

        // Returns false when the clipboard could not be read and the caller should retry.
        bool HandleClipboard()
        {
            uint sequence = Native.GetClipboardSequenceNumber();
            if (sequence == ownSequence)
            {
                return true;    // that update is our own write
            }

            List<string> formats = ClipboardInspector.ListFormats();
            if (formats == null)
            {
                return false;
            }
            if (!ClipboardInspector.IsPlainPicture(formats))
            {
                if (ClipboardInspector.HasPicture(formats))
                {
                    Log("left alone (not a plain picture): " + string.Join(", ", formats.ToArray()));
                }
                return true;
            }

            Image image = Clipboard.GetImage();
            if (image == null)
            {
                return true;
            }

            using (image)
            {
                string path = ImageStore.Save(image, imageDirectory);

                // If something else was copied while we saved, leave it alone; that change is handled on its own.
                if (Native.GetClipboardSequenceNumber() != sequence)
                {
                    return true;
                }

                DataObject data = new DataObject();
                data.SetImage(image);
                data.SetText(ImageStore.ToClipboardText(path));
                Clipboard.SetDataObject(data, true, 10, 50);
                ownSequence = Native.GetClipboardSequenceNumber();

                Log("saved " + path + " (" + image.Width + "x" + image.Height + ")");
                SetTrayText("Terminal Board: latest screenshot ready (Ctrl+V)");
                ImageStore.Cleanup(imageDirectory, KeepImages);
            }
            return true;
        }

        // A few seconds after start-up, prepare the settings screen in the background so the first click is instant too.
        void WarmDesk()
        {
            try
            {
                ProcessStartInfo info = new ProcessStartInfo(Application.ExecutablePath, "--desk-warm --data-dir \"" + dataDirectory + "\"");
                info.UseShellExecute = false;
                info.CreateNoWindow = true;
                Process.Start(info);
            }
            catch (Exception ex)
            {
                Log("could not prepare the settings screen: " + ex.Message);
            }
        }

        // Opens the settings screen, so the working window is one double-click away. The screen lives in its
        // own process (started here with --desk on first use); asking again just signals that process.
        void OpenDesk()
        {
            try
            {
                EventWaitHandle server;
                if (EventWaitHandle.TryOpenExisting(DeskServer.ShowSignalName, out server))
                {
                    server.Set();
                    server.Close();
                    return;
                }

                ProcessStartInfo info = new ProcessStartInfo(Application.ExecutablePath, "--desk --data-dir \"" + dataDirectory + "\"");
                info.UseShellExecute = false;
                Process.Start(info);
            }
            catch (Exception ex)
            {
                Log("could not open the settings screen: " + ex.Message);
            }
        }

        void OpenImageFolder()
        {
            try
            {
                Process.Start("explorer.exe", "\"" + imageDirectory + "\"");
            }
            catch (Exception ex)
            {
                Log("could not open folder: " + ex.Message);
            }
        }

        void SetTrayText(string text)
        {
            // NotifyIcon.Text is limited to 63 characters.
            tray.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        static Icon LoadIcon()
        {
            try
            {
                Icon icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                if (icon != null)
                {
                    return icon;
                }
            }
            catch (Exception)
            {
            }
            return SystemIcons.Application;
        }

        void Log(string message)
        {
            try
            {
                string path = Path.Combine(dataDirectory, "helper.log");
                FileInfo info = new FileInfo(path);
                if (info.Exists && info.Length > 200 * 1024)
                {
                    info.Delete();
                }
                File.AppendAllText(
                    path,
                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "] " + message + Environment.NewLine,
                    Encoding.UTF8);
            }
            catch (Exception)
            {
                // Logging must never stop the helper.
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                debounce.Dispose();
                exitPoll.Dispose();
                window.Close();
                tray.Visible = false;
                tray.Dispose();
                exitSignal.Close();
            }
            base.Dispose(disposing);
        }
    }

    internal static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            string dataDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "TerminalBoard");
            bool exitRequested = false;
            bool deskRequested = false;
            bool warmRequested = false;
            bool openSavedRequested = false;
            string snapshotPath = null;
            string printSettingsPath = null;
            string printOutputPath = null;

            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--exit")
                {
                    exitRequested = true;
                }
                else if (args[i] == "--desk")
                {
                    deskRequested = true;
                }
                else if (args[i] == "--desk-warm")
                {
                    warmRequested = true;
                }
                else if (args[i] == "--open")
                {
                    openSavedRequested = true;
                }
                else if (args[i] == "--desk-snapshot" && i + 1 < args.Length)
                {
                    snapshotPath = args[++i];
                }
                else if (args[i] == "--print-board" && i + 2 < args.Length)
                {
                    printSettingsPath = args[++i];
                    printOutputPath = args[++i];
                }
                else if (args[i] == "--data-dir" && i + 1 < args.Length)
                {
                    dataDirectory = args[++i];
                }
            }

            if (exitRequested)
            {
                foreach (string signalName in new string[] { HelperContext.ExitSignalName, DeskServer.ExitSignalName })
                {
                    EventWaitHandle running;
                    if (EventWaitHandle.TryOpenExisting(signalName, out running))
                    {
                        running.Set();
                        running.Close();
                    }
                }
                return 0;
            }

            // The screen code (and the WPF libraries it needs) is only loaded on these paths, never by the tray helper.
            if (printSettingsPath != null)
            {
                return DeskServer.PrintBoard(printSettingsPath, printOutputPath);
            }
            if (snapshotPath != null)
            {
                return DeskServer.Snapshot(dataDirectory, snapshotPath);
            }
            if (openSavedRequested)
            {
                return DeskServer.OpenSaved(dataDirectory);
            }
            if (deskRequested || warmRequested)
            {
                EventWaitHandle server;
                if (EventWaitHandle.TryOpenExisting(DeskServer.ShowSignalName, out server))
                {
                    if (deskRequested)
                    {
                        server.Set();
                    }
                    server.Close();
                    return 0;
                }
                return DeskServer.Run(dataDirectory, deskRequested);
            }

            bool createdNew;
            using (Mutex mutex = new Mutex(true, "Local\\TerminalBoardClipboardHelper", out createdNew))
            {
                if (!createdNew)
                {
                    return 0;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new HelperContext(dataDirectory));
                return 0;
            }
        }
    }
}
