# CSGO-Team-GunGame

Basically Arms-Race but your entire team has the same weapon and you all level up at once. The plugin supports bots, GOTV, all weapons, and custom gun configuration.

---

**This plugin has been only tested using the "Casual" gamemode.**

I recommend you do the same, my server config is within the [server](server) folder.

To setup your own custom configuration visit my [example team gungame configuration file](team_gungame_configuration_example.txt).

---

# Credit

Thanks to [Doc-Holiday](https://forums.alliedmods.net/member.php?u=29625) for providing the [Objective Remover](https://forums.alliedmods.net/showthread.php?p=1771777) plugin.

Thanks to [DarkEnergy](https://forums.alliedmods.net/member.php?u=36589) for providing the [Slay Losers](https://forums.alliedmods.net/showthread.php?t=133756) plugin.

Thanks to [CoolAJ86](https://stackoverflow.com/users/151312/coolaj86) for answering [Nit](https://stackoverflow.com/users/1470607/nit)'s [question on StackOverflow](https://stackoverflow.com/questions/2450954/how-to-randomize-shuffle-a-javascript-array/2450976#2450976) regarding array shuffling which I was able to port from JavaScript to SourcePawn.

*The code which has been copied from their code has been marked [within the source](plugin.sp).*

# Convars
### Custom
- `sm_tgg_randomize_weapon_list`
- - Default: `0`
- - Description: `Should we randomize the weapon list after loading it?`
- `sm_tgg_max_weapons`
- - Default: `0`
- - Description: `Maxmimum amount of weapons in the list. If we have too many the last few weapons will be removed. 0 for infinite`

### Default
- `mp_default_team_winner_no_objective`
- - Due to the way how CSGO voting works at the end of the match this will be used to determine the winner of the match. Using any other way to end the match will result in end-map voting not appearing. 
- `mp_maxrounds`
- - The `notify` flag will be stripped
- - Will automatically be set to `0` when the time runs out and the match ends in a stalemate

# Changelog

**1.0**

- Initial Release
