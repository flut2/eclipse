using System.Diagnostics;
using NLog;

namespace GameServer.realm; 

public class LogicTicker {
	private static Logger Log = LogManager.GetCurrentClassLogger();
	private RealmManager _manager;
	private ManualResetEvent _mre;
	public RealmTime WorldTime;
	public long UsPerTick;
       
	public LogicTicker(RealmManager manager) {
		_manager = manager;
		UsPerTick = 1000 * 1000 / manager.TPS;
		_mre = new ManualResetEvent(initialState: false);
		WorldTime = default;
	}
       
	public void TickLoop() {
		Log.Info("Logic loop started.");
		var loopTime = 0L;
		var t = default(RealmTime);
		while (true) {
			WorldTime.TotalElapsedUs = t.TotalElapsedUs = Stopwatch.GetTimestamp() / 1000L;
			t.TickDelta = loopTime / UsPerTick;
			WorldTime.TickCount = t.TickCount += t.TickDelta;
			WorldTime.ElapsedUsDelta = t.ElapsedUsDelta = loopTime;
			if (_manager.Terminating)
				break;
       			
			_manager.Monitor.Tick(t);
			_manager.InterServer.Tick(t.ElapsedUsDelta);
			WorldTime.TickDelta += t.TickDelta;
			foreach (var w in _manager.Worlds.Values)
				w.Tick(t);
       			
			t.TickDelta = WorldTime.TickDelta;
			WorldTime.ElapsedUsDelta = t.ElapsedUsDelta = t.TickDelta * UsPerTick;
			WorldTime.TickDelta = 0;
			var logicTime = Stopwatch.GetTimestamp() / 1000L - t.TotalElapsedUs;
			_mre.WaitOne((int)Math.Max(0, (UsPerTick - logicTime) / 1000f));
			loopTime = Stopwatch.GetTimestamp() / 1000L - t.TotalElapsedUs;
		}
            
		Log.Info("Logic loop stopped.");
	}
}