using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using TokenStats.Model;

namespace TokenStats.UI;

/// <summary>
/// Zeichnet das Tray-Symbol in den drei Anzeige-Modi (SPEC §2).
///
/// Anders als die macOS-Menüleiste ist der Infobereich quadratisch und nur 16 px (bei 100 %)
/// groß. Darum steht bei „Icon + %“ die Zahl allein im Symbol, und bei „Icon + Balken“
/// rückt der Roboter über die beiden Balken.
/// </summary>
public static class StatusIcon
{
    public sealed record Input(
        MenuBarMode Mode,
        Severity? Severity,     // null = noch keine Daten
        double? Percent,
        IReadOnlyList<double> Bars,   // oben Session, unten Woche
        bool Colored,
        bool Paused,            // Rate-Limit aktiv
        bool TaskbarDark);

    public static BitmapSource Render(Input input, int size)
    {
        // Ohne Zustandsfarbe oder ohne Daten: Farbe der Taskleiste, wie ein Template-Symbol auf macOS.
        int? tint = input.Colored && input.Severity is { } severity
            ? Palette.SeverityColor(severity, input.TaskbarDark) : null;
        var plainColor = input.TaskbarDark ? 0xFFFFFF : 0x000000;
        var color = tint ?? plainColor;
        var brush = Palette.Solid(color);
        double s = size;

        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            var reserveRight = input.Paused ? s * 0.22 : 0;
            switch (input.Mode)
            {
                case MenuBarMode.Icon:
                    RobotGlyph.DrawFitted(context, new Rect(0, 0, s, s), brush, minLine: 1.3);
                    break;

                case MenuBarMode.IconPercent:
                    var label = input.Percent is { } percent
                        ? ((int)Math.Round(percent * 100, MidpointRounding.AwayFromZero)).ToString(CultureInfo.InvariantCulture)
                        : "–";
                    var width = s - reserveRight;
                    var text = Text(label, s * 0.78, brush);
                    if (text.Width > width) text = Text(label, s * 0.78 * width / text.Width, brush);
                    context.DrawText(text, new Point((width - text.Width) / 2, (s - text.Height) / 2));
                    break;

                case MenuBarMode.IconBars:
                    var barHeight = Math.Max(2, Math.Round(s / 8));
                    var gap = Math.Max(1, Math.Round(s / 16));
                    RobotGlyph.DrawFitted(context, new Rect(0, 0, s, s - 2 * barHeight - 2 * gap), brush, minLine: 1.1);
                    for (var row = 0; row < Math.Min(2, input.Bars.Count); row++)
                    {
                        var value = input.Bars[row];
                        var y = s - (2 - row) * barHeight - (1 - row) * gap;
                        context.DrawRectangle(Palette.Solid(color, 0x55), null, new Rect(0, y, s, barHeight));
                        var fill = tint is null ? plainColor : Palette.SeverityColor(SeverityOf.Percent(value), input.TaskbarDark);
                        context.DrawRectangle(Palette.Solid(fill), null, new Rect(0, y, s * Math.Clamp(value, 0, 1), barHeight));
                    }
                    break;
            }
            if (input.Paused)
            {
                // Pause-Symbol oben rechts: letzte Werte, Abfrage ruht wegen Rate-Limit.
                var w = Math.Max(1, Math.Round(s / 12));
                var h = Math.Round(s * 0.3);
                context.DrawRectangle(brush, null, new Rect(s - 3 * w, 0, w, h));
                context.DrawRectangle(brush, null, new Rect(s - w, 0, w, h));
            }
        }

        var bitmap = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        bitmap.Freeze();
        return bitmap;
    }

    static FormattedText Text(string text, double size, Brush brush) => new(
        text, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
        new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.SemiCondensed),
        size, brush, 1.0);
}
