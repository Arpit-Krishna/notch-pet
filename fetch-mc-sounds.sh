#!/bin/bash
# Downloads each pet's voice clips from minecraft.wiki (MP3 transcodes) into
# ~/Library/Application Support/NotchPet/sounds/<pet>/<alert>-<name>.mp3, where Pip picks them up.
# These are Mojang's sounds: for personal use on your own Mac only, never commit or share them.
# Without these files Pip uses its own synthesized voices. Classic Pip always does.
set -uo pipefail
DEST="$HOME/Library/Application Support/NotchPet/sounds"
BASE="https://minecraft.wiki/images/transcoded"

# pet        alert    wiki file names (spaces as underscores)
MAP=(
  "villager   waiting  Villager_idle1 Villager_idle2 Villager_idle3"
  "villager   done     Villager_accept1 Villager_accept2"
  "villager   error    Villager_deny1 Villager_deny2"
  "villager   select   Villager_trade1"
  "wolf       waiting  Wolf_idle1 Wolf_idle2"
  "wolf       done     Wolf_howl1 Wolf_howl2"
  "wolf       error    Wolf_whine"
  "wolf       select   Wolf_panting"
  "warden     waiting  Warden_heartbeat1 Warden_heartbeat2"
  "warden     done     Warden_ambient1 Warden_ambient2 Warden_ambient3"
  "warden     error    Warden_angry1 Warden_angry2"
  "warden     select   Warden_listening1"
  "zombie     waiting  Zombie_idle1 Zombie_idle2 Zombie_idle3"
  "zombie     done     Zombie_unfect"
  "zombie     error    Zombie_hurt1 Zombie_hurt2"
  "zombie     select   Zombie_idle1"
  "cat        waiting  Cat_beg1 Cat_beg2 Cat_beg3"
  "cat        done     Cat_purreow1 Cat_purreow2"
  "cat        error    Cat_hiss1 Cat_hiss2"
  "cat        select   Cat_purr1"
  "creeper    waiting  Creeper_fuse"
  "creeper    done     Random_levelup"
  "creeper    error    Creeper_hurt1 Creeper_hurt2"
  "creeper    select   Fuse"
  "pig        waiting  Pig_idle1 Pig_idle2"
  "pig        done     Pig_idle3"
  "pig        error    Pig_death"
  "pig        select   Pig_idle1"
  "cow        waiting  Cow_idle1 Cow_idle2"
  "cow        done     Cow_milk1"
  "cow        error    Cow_hurt1 Cow_hurt2"
  "cow        select   Cow_idle3"
  "sheep      waiting  Sheep1 Sheep2"
  "sheep      done     Sheep3"
  "sheep      error    Sheep1"
  "sheep      select   Sheep2"
  "chicken    waiting  Chicken_idle1 Chicken_idle2"
  "chicken    done     Chicken_plop"
  "chicken    error    Chicken_hurt1 Chicken_hurt2"
  "chicken    select   Chicken_idle3"
  "fox        waiting  Fox_screech1 Fox_screech2"
  "fox        done     Fox_idle1 Fox_idle2"
  "fox        error    Fox_hurt1 Fox_hurt2"
  "fox        select   Fox_sniff1"
  "bee        waiting  Bee_aggressive1"
  "bee        done     Bee_pollinate1 Bee_pollinate2"
  "bee        error    Bee_hurt1 Bee_hurt2"
  "bee        select   Bee_pollinate3"
  "axolotl    waiting  Axolotl_idle_air1 Axolotl_idle_air2"
  "axolotl    done     Axolotl_idle1 Axolotl_idle2"
  "axolotl    error    Axolotl_hurt1 Axolotl_hurt2"
  "axolotl    select   Axolotl_idle3"
  "steve      waiting  Pop"
  "steve      done     Random_levelup"
  "steve      error    Player_hurt1 Player_hurt2"
  "steve      select   Pop"
  "alex       waiting  Pop"
  "alex       done     Random_levelup"
  "alex       error    Player_hurt1 Player_hurt2"
  "alex       select   Pop"
  "notch      waiting  Pop"
  "notch      done     Random_levelup"
  "notch      error    Player_hurt1 Player_hurt2"
  "notch      select   Pop"
  "herobrine  waiting  Cave1 Cave13"
  "herobrine  done     Cave2"
  "herobrine  error    Cave3 Cave14"
  "herobrine  select   Cave13"
  "grassBlock waiting  Grass_hit1 Grass_hit2"
  "grassBlock done     Grass_dig1 Grass_dig2"
  "grassBlock error    Grass_mining1"
  "grassBlock select   Grass_dig3"
)

saved=0; failed=0
for row in "${MAP[@]}"; do
  read -r pet alert names <<<"$row"
  mkdir -p "$DEST/$pet"
  for name in $names; do
    out="$DEST/$pet/$alert-$name.mp3"
    [ -s "$out" ] && continue
    if curl -fsSL -A "NotchPet/0.1" "$BASE/$name.ogg/$name.ogg.mp3" -o "$out"; then
      saved=$((saved + 1))
    else
      rm -f "$out"; failed=$((failed + 1)); echo "missing on wiki: $name ($pet $alert)"
    fi
  done
done
echo "saved $saved clips, $failed missing → $DEST"
