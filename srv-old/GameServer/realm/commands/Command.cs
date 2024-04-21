using GameServer.realm.entities.player;
using NLog;

namespace GameServer.realm.commands; 

public abstract class Command
{
    protected static readonly Logger Log = LogManager.GetCurrentClassLogger();

    public string CommandName;
    public string[] Aliases;
    public int PermissionLevel;
    public bool ListCommand;
    protected string CommandTag;

    protected Command(string name, int permLevel = 0, bool listCommand = true, params string[] aliases)
    {
        CommandName = name;
        PermissionLevel = permLevel;
        ListCommand = listCommand;
        Aliases = aliases;
    }

    protected abstract bool Process(Player player, RealmTime time, string args);

    private static int GetPermissionLevel(Player player)
    {
        return player.Client.Account.Rank;
    }

    public bool HasPermission(Player player)
    {
        return GetPermissionLevel(player) >= PermissionLevel;
    }

    public bool Execute(Player player, RealmTime time, string cmdTag, string args, bool bypassPermission = false)
    {
        if (!bypassPermission && !HasPermission(player))
        {
            player.SendError("No permission!");
            return false;
        }

        try
        {
            CommandTag = cmdTag.ToLower();
            return Process(player, time, args);
        }
        catch (Exception ex)
        {
            Log.Error("Error when executing the command.", ex);
            player.SendError("Error when executing the command.");
            return false;
        }
    }
}

public class CommandManager
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    private RealmManager _manager;
    private readonly Dictionary<string, Command> _cmds;

    public IDictionary<string, Command> Commands => _cmds;

    public CommandManager(RealmManager manager)
    {
        _manager = manager;
        _cmds = new Dictionary<string, Command>(StringComparer.InvariantCultureIgnoreCase);
        var t = typeof(Command);
        foreach (var i in t.Assembly.GetTypes())
            if (t.IsAssignableFrom(i) && i != t)
            {
                var instance = (i.GetConstructor(new Type[] { typeof(RealmManager) }) == null)
                    ? (Command)Activator.CreateInstance(i)
                    : (Command)Activator.CreateInstance(i, manager);
                _cmds.Add(instance.CommandName, instance);
                if (instance.Aliases != null)
                    for (var j = 0; j < instance.Aliases.Length; j++) 
                        _cmds.Add(instance.Aliases[j], instance);
            }
    }

    public bool Execute(Player player, RealmTime time, string text)
    {
        var index = text.IndexOf(' ');
        var cmd = text.Substring(1, index == -1 ? text.Length - 1 : index - 1);
        var args = index == -1 ? "" : text.Substring(index + 1);

        Command command;
        if (!_cmds.TryGetValue(cmd, out command))
        {
            player.SendError("Unknown command!");
            return false;
        }

        var owner = player.Owner;
        Log.Info("[Command] [{0}] <{1}> {2}", owner?.Name ?? "", player.Name, text);
        return command.Execute(player, time, cmd, args);
    }
}