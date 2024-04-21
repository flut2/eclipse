using GameServer.realm.worlds.logic;

namespace GameServer.realm.entities.player; 

partial class Player
{
    internal Dictionary<Player, long> potentialTrader = new();
    internal Player tradeTarget;
    internal bool[] trade;
    internal bool tradeAccepted;

    public void RequestTrade(string name)
    {
        Manager.Database.ReloadAccount(_client.Account);
        var acc = _client.Account;
            
        if (tradeTarget != null)
        {
            SendError("Already trading!");
            return;
        }

        var target = Owner.GetUniqueNamedPlayer(name);
        if (target == null || !target.CanBeSeenBy(this))
        {
            SendError(name + " not found!");
            return;
        }

        if (target == this)
        {
            SendError("You can't trade with yourself!");
            return;
        }

        if (target._client.Account.IgnoreList.Contains(AccountId))
            return; // account is ignored

        if (target.tradeTarget != null)
        {
            SendError(target.Name + " is already trading!");
            return;
        }

        if (potentialTrader.ContainsKey(target))
        {
            tradeTarget = target;
            trade = new bool[22];
            tradeAccepted = false;
            target.tradeTarget = this;
            target.trade = new bool[22];
            target.tradeAccepted = false;
            potentialTrader.Clear();
            target.potentialTrader.Clear();

            // shouldn't be needed since there is checks on
            // invswap, invdrop, and useitem packets for trading
            //MonitorTrade();
            //target.MonitorTrade();

            var my = new TradeItem[22];
            for (var i = 0; i < 22; i++)
                my[i] = new TradeItem()
                {
                    Item = Inventory[i].ObjectType,
                    SlotType = SlotTypes[i],
                    Included = false,
                    Tradeable = Inventory[i] != null && i >= 4 && !Inventory[i].Untradable
                };
            var your = new TradeItem[22];
            for (var i = 0; i < 22; i++)
                your[i] = new TradeItem()
                {
                    Item = target.Inventory[i].ObjectType,
                    SlotType = target.SlotTypes[i],
                    Included = false,
                    Tradeable = target.Inventory[i] != null && i >= 4 && !target.Inventory[i].Untradable
                };
            _client.SendTradeStart(my, target.Name, your);
            target._client.SendTradeStart(your, Name, my);
        }
        else
        {
            target.potentialTrader[this] = 1000 * 1000 * 20;
            target._client.SendTradeRequested(Name);
            SendInfo("You have sent a trade request to " + target.Name + "!");
            return;
        }
    }

    public void CancelTrade()
    {
        _client.SendTradeDone(1, $"Trade canceled!");

        if (tradeTarget != null && tradeTarget._client != null)
            tradeTarget._client.SendTradeDone(1, $"Trade Canceled!");
        ResetTrade();
    }

    public void ResetTrade()
    {
        if (tradeTarget != null)
        {
            tradeTarget.tradeTarget = null;
            tradeTarget.trade = null;
            tradeTarget.tradeAccepted = false;
        }

        tradeTarget = null;
        trade = null;
        tradeAccepted = false;
    }

    private void CheckTradeTimeout(RealmTime time)
    {
        var newState = new List<Tuple<Player, long>>();
        foreach (var i in potentialTrader)
            newState.Add(new Tuple<Player, long>(i.Key, i.Value - time.ElapsedUsDelta));

        foreach (var i in newState)
        {
            if (i.Item2 < 0)
            {
                i.Item1.SendInfo("Trade to " + Name + " has timed out!");
                potentialTrader.Remove(i.Item1);
            }
            else potentialTrader[i.Item1] = i.Item2;
        }
    }
}