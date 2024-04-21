namespace Shared; 

public static class MathUtils
{
    public static readonly Random Random = new();

    public static double NextDouble()
    {
        return Random.NextDouble();
    }

    public static int Next(int max)
    {
        return (int)(NextDouble() * max);
    }

    public static int Next(int min, int max)
    {
        return min + (int)(NextDouble() * (max - min));
    }
        
    public static double DistSqr(double x1, double y1, double x2, double y2) {
        var dx = x1 - x2;
        var dy = y1 - y2;
        return dx * dx + dy * dy;
    }
}