namespace GameServer.realm; 

public class ActivateBoost
{
    private readonly List<int> _stack;
    private List<int> _base;
    private int _offset;

    public ActivateBoost()
    {
        _stack = new List<int>();
        _base = new List<int> { 0 };
    }

    public int GetBoost()
    {
        var boost = 0;
        for (var i = 0; i < _stack.Count; i++)
            boost += (int)(_stack[_stack.Count - 1 - i] * Math.Pow(.5, i));

        boost += _base[0];
        boost += _offset;
        return boost;
    }

    public void Push(int amount)
    {
        _stack.Add(amount);
        _stack.Sort();
    }

    public void Pop(int amount)
    {
        if (_stack.Count <= 0)
            return;

        _stack.Remove(amount);
        _stack.Sort();
    }

    public void AddOffset(int amount)
    {
        _offset += amount;
    }

    public void PopAll()
    {
        // doing it like this because wserver will throw errors otherwise
        for (var i = 0; i < _stack.Count; i++)
            _stack[i] = 0;
        for (var i = 0; i < _base.Count; i++)
            _base[i] = 0;
    }
}