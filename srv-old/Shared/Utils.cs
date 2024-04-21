using System.ComponentModel;
using System.Globalization;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Ionic.Zlib;
using Newtonsoft.Json;

namespace Shared; 

public static class Utils
{
    public static JsonSerializerSettings SerializerSettings()
    {
        return new JsonSerializerSettings
        {
            NullValueHandling = NullValueHandling.Ignore,
            DefaultValueHandling = DefaultValueHandling.Ignore,
        };
    }

    public static byte[] ToUtf8Bytes(this string val)
    {
        return Encoding.UTF8.GetBytes(val);
    }

    public static XElement AddAttribute(this XElement elem, XName name, object value)
    {
        elem.SetAttributeValue(name, value);
        return elem;
    }

    public static T PickRandom<T>(this IEnumerable<T> source)
    {
        return source.PickRandom(1).Single();
    }

    public static IEnumerable<T> PickRandom<T>(this IEnumerable<T> source, int count)
    {
        return source.Shuffle().Take(count);
    }

    public static IEnumerable<T> Shuffle<T>(this IEnumerable<T> source)
    {
        return source.OrderBy(x => Guid.NewGuid());
    }

    public static bool IsInt(this string str)
    {
        int dummy;
        return Int32.TryParse(str, out dummy);
    }

    public static int ToInt32(this string str)
    {
        return FromString(str);
    }

    public static T[] ResizeArray<T>(T[] array, int newSize)
    {
        var inventory = new T[newSize];
        for (var i = 0; i < (array.Length > inventory.Length ? inventory.Length : array.Length); i++)
            inventory[i] = array[i];

        return inventory;
    }

    public static string GetBasePath(string folder)
    {
        return Path.Combine(GetAssemblyDirectory(), folder);
    }

    public static string GetAssemblyDirectory()
    {
        var codeBase = Assembly.GetExecutingAssembly().CodeBase;
        var uri = new UriBuilder(codeBase);
        var path = Uri.UnescapeDataString(uri.Path);
        return Path.GetDirectoryName(path);
    }

    public static byte[] Deflate(string src)
    {
        var bytes = Encoding.UTF8.GetBytes(src);
        return Deflate(bytes);
    }

    public static byte[] Deflate(byte[] src)
    {
        byte[] zipBytes;

        using (var dst = new MemoryStream())
        {
            using (var df = new DeflateStream(dst, CompressionMode.Compress))
                df.Write(src, 0, src.Length);

            zipBytes = dst.ToArray();
        }

        return zipBytes;
    }

    public static int FromString(string x, int def = 0)
    {
        var val = def;
        try
        {
            val = x.StartsWith("0x") ? int.Parse(x.Substring(2), NumberStyles.HexNumber) : int.Parse(x);
        }
        catch
        {
        }

        return val;
    }

    public static string To4Hex(this ushort x)
    {
        return "0x" + x.ToString("x4");
    }

    public static string ToCommaSepString<T>(this T[] arr)
    {
        var ret = new StringBuilder();
        for (var i = 0; i < arr.Length; i++)
        {
            if (i != 0) ret.Append(", ");
            ret.Append(arr[i]);
        }

        return ret.ToString();
    }

    public static T[] CommaToArray<T>(this string x)
    {
        if (typeof(T) == typeof(ushort))
            return x.Split(',').Select(_ => (T)(object)(ushort)FromString(_.Trim())).ToArray();
        if (typeof(T) == typeof(string))
            return x.Split(',').Select(_ => (T)(object)_.Trim()).ToArray();
        //assume int
        return x.Split(',').Select(_ => (T)(object)FromString(_.Trim())).ToArray();
    }

    public static byte[] SHA1(string val)
    {
        var sha1 = new SHA1Managed();
        return sha1.ComputeHash(Encoding.UTF8.GetBytes(val));
    }

    public static int ToUnixTimestamp(this DateTime dateTime)
    {
        return (int)(dateTime - new DateTime(1970, 1, 1)).TotalSeconds;
    }

    public static T Exec<T>(this Task<T> task)
    {
        task.Wait();
        return task.Result;
    }

    public static void Shuffle<T>(this IList<T> list)
    {
        var provider = new RNGCryptoServiceProvider();
        var n = list.Count;
        while (n > 1)
        {
            var box = new byte[1];
            do provider.GetBytes(box);
            while (!(box[0] < n * (Byte.MaxValue / n)));
            var k = (box[0] % n);
            n--;
            var value = list[k];
            list[k] = list[n];
            list[n] = value;
        }
    }

    public static bool IsValidEmail(string strIn)
    {
        var invalid = false;
        if (String.IsNullOrEmpty(strIn))
            return false;

        MatchEvaluator domainMapper = match =>
        {
            // IdnMapping class with default property values.
            var idn = new IdnMapping();

            var domainName = match.Groups[2].Value;
            try
            {
                domainName = idn.GetAscii(domainName);
            }
            catch (ArgumentException)
            {
                invalid = true;
            }

            return match.Groups[1].Value + domainName;
        };

        // Use IdnMapping class to convert Unicode domain names. 
        strIn = Regex.Replace(strIn, @"(@)(.+)$", domainMapper);
        if (invalid)
            return false;

        // Return true if strIn is in valid e-mail format. 
        return Regex.IsMatch(strIn,
            @"^(?("")(""[^""]+?""@)|(([0-9a-z]((\.(?!\.))|[-!#\$%&'\*\+/=\?\^`\{\}\|~\w])*)(?<=[0-9a-z])@))" +
            @"(?(\[)(\[(\d{1,3}\.){3}\d{1,3}\])|(([0-9a-z][-\w]*[0-9a-z]*\.)+[a-z0-9]{2,17}))$",
            RegexOptions.IgnoreCase);
    }

    public static string GetDescription(this Enum value)
    {
        var type = value.GetType();
        var name = Enum.GetName(type, value);
        if (name != null)
        {
            var field = type.GetField(name);
            if (field != null)
            {
                var attr =
                    Attribute.GetCustomAttribute(field,
                        typeof(DescriptionAttribute)) as DescriptionAttribute;
                return attr?.Description;
            }
        }

        return null;
    }

    public static T FromJson<T>(string json) where T : class
    {
        if (String.IsNullOrWhiteSpace(json)) return null;
        var jsonSerializer = new JsonSerializer();
        using (var strRdr = new StringReader(json))
        using (var jsRdr = new JsonTextReader(strRdr))
            return jsonSerializer.Deserialize<T>(jsRdr);
    }

    public static DateTime FromUnixTimestamp(int time)
    {
        var dateTime = new DateTime(1970, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc);
        dateTime = dateTime.AddSeconds(time).ToLocalTime();
        return dateTime;
    }

    // https://www.codeproject.com/Articles/770323/How-to-Convert-a-Date-Time-to-X-minutes-ago-in-Csh
    public static string TimeAgo(DateTime dt)
    {
        var span = DateTime.Now - dt;
        if (span.Days > 365)
        {
            var years = (span.Days / 365);
            if (span.Days % 365 != 0)
                years += 1;
            return $"{years} {(years == 1 ? "year" : "years")} ago";
        }

        if (span.Days > 30)
        {
            var months = (span.Days / 30);
            if (span.Days % 31 != 0)
                months += 1;
            return $"{months} {(months == 1 ? "month" : "months")} ago";
        }

        if (span.Days > 0)
            return $"{span.Days} {(span.Days == 1 ? "day" : "days")} ago";
        if (span.Hours > 0)
            return $"{span.Hours} {(span.Hours == 1 ? "hour" : "hours")} ago";
        if (span.Minutes > 0)
            return $"{span.Minutes} {(span.Minutes == 1 ? "minute" : "minutes")} ago";
        if (span.Seconds > 5)
            return $"{span.Seconds} seconds ago";
        if (span.Seconds <= 5)
            return "just now";
        return string.Empty;
    }

    public static bool HasElement(this XElement e, string name)
    {
        return e.Element(name) != null;
    }

    public static bool HasAttribute(this XElement e, string name)
    {
        return e.Attribute(name) != null;
    }

    public static int GetInt(string x)
    {
        return x.Contains("x") ? Convert.ToInt32(x, 16) : int.Parse(x);
    }

        
        
    public static ConditionEffectIndex GetEffect(string val)
    {
        return (ConditionEffectIndex)Enum.Parse(typeof(ConditionEffectIndex), val.Trim());
    }
        
    public static bool TryGetEffect(string val, out ConditionEffectIndex effect)
    {
        return Enum.TryParse(val.Trim(), out effect);
    }

    public static T GetValue<T>(this XElement e, string n, T def = default(T))
    {
        if (e.Element(n) == null)
            return def;

        var val = e.Element(n).Value;
        var t = typeof(T);
        if (t == typeof(string))
            return (T)Convert.ChangeType(val, t);
        if (t == typeof(ushort))
            return (T)Convert.ChangeType(Convert.ToUInt16(val, 16), t);
        if (t == typeof(int))
            return (T)Convert.ChangeType(GetInt(val), t);
        if (t == typeof(uint))
            return (T)Convert.ChangeType(Convert.ToUInt32(val, 16), t);
        if (t == typeof(double))
            return (T)Convert.ChangeType(double.Parse(val, CultureInfo.InvariantCulture), t);
        if (t == typeof(float))
            return (T)Convert.ChangeType(float.Parse(val, CultureInfo.InvariantCulture), t);
        if (t == typeof(bool))
            return (T)Convert.ChangeType(string.IsNullOrWhiteSpace(val) || bool.Parse(val), t);

        return def;
    }

    public static T GetAttribute<T>(this XElement e, string n, T def = default(T))
    {
        if (e.Attribute(n) == null)
            return def;

        var val = e.Attribute(n).Value;
        var t = typeof(T);
        if (t == typeof(string))
            return (T)Convert.ChangeType(val, t);
        if (t == typeof(ushort))
            return (T)Convert.ChangeType(Convert.ToUInt16(val, 16), t);
        if (t == typeof(int))
            return (T)Convert.ChangeType(GetInt(val), t);
        if (t == typeof(uint))
            return (T)Convert.ChangeType(Convert.ToUInt32(val, 16), t);
        if (t == typeof(double))
            return (T)Convert.ChangeType(double.Parse(val, CultureInfo.InvariantCulture), t);
        if (t == typeof(float))
            return (T)Convert.ChangeType(float.Parse(val, CultureInfo.InvariantCulture), t);
        if (t == typeof(bool))
            return (T)Convert.ChangeType(string.IsNullOrWhiteSpace(val) || bool.Parse(val), t);

        return def;
    }

    public static string ReadFile(string path)
    {
        return File.ReadAllText(path);
    }

    public static void WriteFile(string path, string contents)
    {
        File.WriteAllText(path, contents);
    }
        
    public static string GetBuildConfig()
    {
#if DEBUG
            return "debug";
#else
        return "release";
#endif
    }
}

public static class StringUtils
{
    public static bool ContainsIgnoreCase(this string self, string val)
    {
        return self.IndexOf(val, StringComparison.InvariantCultureIgnoreCase) != -1;
    }

    public static bool EqualsIgnoreCase(this string self, string val)
    {
        return self.Equals(val, StringComparison.InvariantCultureIgnoreCase);
    }

    public static byte[] StringToByteArray(string hex)
    {
        return Enumerable.Range(0, hex.Length)
            .Where(x => x % 2 == 0)
            .Select(x => Convert.ToByte(hex.Substring(x, 2), 16))
            .ToArray();
    }
}
    
public static class ParseUtils
{
    public static string ParseString(this XElement element, string name, string undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return value;
    }

    public static int ParseInt(this XElement element, string name, int undefined = 0)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return Utils.FromString(value, undefined);
    }
        
    private static int? NFromString(string x, int? undefined = null)
    {
        var val = undefined;
        try
        {
            val = x.StartsWith("0x") ? int.Parse(x.Substring(2), NumberStyles.HexNumber) : int.Parse(x);
        }
        catch { }
            
        return val;
    }
        
    public static int? ParseNInt(this XElement element, string name, int? undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return NFromString(value, undefined);
    }

    public static long ParseLong(this XElement element, string name, long undefined = 0)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return long.Parse(value);
    }

    public static uint ParseUInt(this XElement element, string name, bool isHex = true, uint undefined = 0)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return Convert.ToUInt32(value, isHex ? 16 : 10);
    }

    public static float ParseFloat(this XElement element, string name, float undefined = 0)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return float.Parse(value, CultureInfo.InvariantCulture);
    }

    public static float? ParseNFloat(this XElement element, string name, float? undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return float.Parse(value, CultureInfo.InvariantCulture);
    }

    public static bool ParseBool(this XElement element, string name, bool undefined = false)
    {
        var isAttr = name[0].Equals('@');
        var id = name[0].Equals('@') ? name.Remove(0, 1) : name;
        var value = isAttr ? element.Attribute(id)?.Value : element.Element(id)?.Value;
        if (string.IsNullOrWhiteSpace(value)) 
        {
            if (isAttr && element.Attribute(id) != null || !isAttr && element.Element(id) != null)
                return true;
            return undefined; 
        }
        return bool.Parse(value);
    }

    public static ushort ParseUshort(this XElement element, string name, ushort undefined = 0)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return (ushort)(value.StartsWith("0x") ? int.Parse(value.Substring(2), NumberStyles.HexNumber) : int.Parse(value));
    }

    public static ConditionEffectIndex ParseConditionEffect(this XElement element, string name, ConditionEffectIndex undefined = ConditionEffectIndex.Dead)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value))
            return undefined;
        return (ConditionEffectIndex)Enum.Parse(typeof(ConditionEffectIndex), value.Replace(" ", ""));
    }
        
    public static string[] ParseStringArray(this XElement element, string name, char seperator, string[] undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        return value.Split(seperator);
    }

    public static int[] ParseIntArray(this XElement element, string name, char seperator, int[] undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        value = Regex.Replace(value, @"\s+", "");
        return ParseStringArray(element, name, seperator).Select(k => int.Parse(k)).ToArray();
    }

    public static ushort[] ParseUshortArray(this XElement element, string name, char seperator, ushort[] undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        value = Regex.Replace(value, @"\s+", "");
        return ParseStringArray(element, name, seperator).Select(k => (ushort)(k.StartsWith("0x") ? Int32.Parse(k.Substring(2), NumberStyles.HexNumber) : Int32.Parse(k))).ToArray();
    }

    public static float[] ParseFloatArray(this XElement element, string name, char seperator, float[] undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        value = Regex.Replace(value, @"\s+", "");
        return ParseStringArray(element, name, seperator).Select(k => float.Parse(k)).ToArray();
    }

    public static double[] ParseDoubleArray(this XElement element, string name, char seperator, double[] undefined = null)
    {
        var value = name[0].Equals('@') ? element.Attribute(name.Remove(0, 1))?.Value : element.Element(name)?.Value;
        if (string.IsNullOrWhiteSpace(value)) return undefined;
        value = Regex.Replace(value, @"\s+", "");
        return ParseStringArray(element, name, seperator).Select(k => double.Parse(k)).ToArray();
    }
}