using Shared;
using Shared.resources;

namespace GameServer.realm.entities.player
{
    partial class Player
    {
        private AbilityDesc[] Abilities = new AbilityDesc[4];
        private long[] LastAbilityUseTime = new long[4];

        private void LoadAbilities()
        {
            var playerDesc = Manager.Resources.GameData.Classes[ObjectType];
            for (var i = 0; i < 4; i++)
                Abilities[i] = playerDesc.Abilities[i];
        }

        public bool TryUseAbility(long time, AbilitySlotType abilitySlotType, byte[] data)
        {
            Console.WriteLine("Time: " + time + " AbilitySlotType: " + abilitySlotType + " Data Length: " + data.Length);
            var index = (int)abilitySlotType;
            if (!CanUseAbility(time, index))
                return false;

            MP -= Abilities[index].ManaCost;
            HP -= Abilities[index].HealthCost;
            LastAbilityUseTime[index] = time;
            UseAbility(data, index);
            return true;
        }

        private bool CanUseAbility(long time, int index) {
            if (MP < Abilities[index].ManaCost || HP < Abilities[index].HealthCost - 1)
                return false;
            
            var delta = time - LastAbilityUseTime[index];
            return delta >= Abilities[index].CooldownMS * 0.95; // account for ping (scuffed)
        }

        private void UseAbility(byte[] data, int index)
        {
            using var rdr = new BinaryReader(new MemoryStream(data));

            var ability = Abilities[index];

            switch (ability.AbilityType)
            {
                case AbilityType.AnomalousBurst:
                    DoAnomalousBurst(rdr);
                    break;
                case AbilityType.ParadoxicalShift:
                    DoParadoxicalShift(rdr);
                    break;
                case AbilityType.Swarm:
                    DoSwarm(rdr);
                    break;
                case AbilityType.Shapeshift:
                    DoShapeshift(rdr);
                    break;
            }
        }

        private void DoAnomalousBurst(BinaryReader rdr) {
            var angle = rdr.ReadSingle();
            var prjDesc = ObjectDesc.Projectiles[0];

            var numProjs = 6 + Math.Floor(Stats[6] / 30.0);
            const double arcGap = 12 * (Math.PI / 180);

            var attackAngleLeft = angle - Math.PI / 2;
            var leftProjs = Math.Ceiling(numProjs / 2.0);
            var leftAngle = attackAngleLeft - arcGap * (leftProjs - 1);
            for (var i = 0; i < leftProjs; i++) {
                var prj = PlayerShootProjectile(bulletId, prjDesc, ObjectType, (float) (Math.Cos(attackAngleLeft) * 0.25), (float) (Math.Sin(attackAngleLeft) * 0.25));
                Owner.EnterWorld(prj);
            
                foreach (var plr in Owner.Players.Values)
                    if (plr.Id != Id && MathUtils.DistSqr(plr.X, plr.Y, X, Y) < 16 * 16)
                        plr.Client.SendAllyShoot(prj.BulletId, Id, prj.Container, (float) leftAngle);
                leftAngle += arcGap;
            }

            var attackAngleRight = angle + Math.PI / 2;
            var rightProjs = numProjs - leftProjs;
            var rightAngle = attackAngleRight - arcGap * (rightProjs - 1);
            for (var i = 0; i < rightProjs; i++) {
                var prj = PlayerShootProjectile(bulletId, prjDesc, ObjectType, (float) (Math.Cos(attackAngleRight) * 0.25), (float) (Math.Sin(attackAngleRight) * 0.25));
                Owner.EnterWorld(prj);
            
                foreach (var plr in Owner.Players.Values)
                    if (plr.Id != Id && MathUtils.DistSqr(plr.X, plr.Y, X, Y) < 16 * 16)
                        plr.Client.SendAllyShoot(prj.BulletId, Id, prj.Container, (float) rightAngle);
                rightAngle += arcGap;
            }
        }

        private void DoParadoxicalShift(BinaryReader rdr) {
            var amount = (int) (Stats[6] * 0.25);
            var duration = 3000;
            ApplyConditionEffect(ConditionEffectIndex.Invisible, duration);
            Stats.Boost.ActivateBoost[6].Push(amount);
            Stats.ReCalculateValues();
            
            Owner.Timers.Add(new WorldTimer(duration, (_, _) => {
                Stats.Boost.ActivateBoost[6].Pop(amount);
                Stats.ReCalculateValues();
            }));
        }

        private void DoSwarm(BinaryReader rdr)
        {
            Console.WriteLine($"Swarm: No Data");
        }

        private void DoShapeshift(BinaryReader rdr)
        {
            var objectId = rdr.ReadInt32();
            Console.WriteLine($"DoShapeshift: {objectId}");
        }
    }
}
