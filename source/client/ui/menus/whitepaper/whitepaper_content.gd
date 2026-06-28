class_name WhitepaperContent
## The in-app whitepaper, as BBCode for a RichTextLabel. Canonical Markdown copy
## lives in docs/whitepaper.md - keep them roughly in sync.

const TITLE: String = "Mythreach - Whitepaper"
const SUBTITLE: String = "v0.1 (Alpha) - A wallet-native, real-time fantasy MMO on Solana"

const BBCODE: String = """[font_size=20][b][color=#e7b26a]1. Abstract[/color][/b][/font_size]
Mythreach is a browser-playable, real-time multiplayer fantasy MMORPG where your [b]Solana wallet is your identity[/b]. No usernames, no passwords, no email - connect your wallet, sign a message, and you're in the world. It pairs a classic top-down MMO (combat, leveling, crafting, guilds, dungeons, parties) with the ownership a wallet-native account makes possible.

[font_size=20][b][color=#e7b26a]2. Vision[/color][/b][/font_size]
Most "web3 games" bolt a token onto a shallow loop. Mythreach inverts that: build a [i]genuinely fun MMO first[/i], then let the wallet unlock what only crypto can - true account ownership, a player-driven economy, and assets that can one day live on-chain.
[indent]- [b]Play in seconds[/b] - open a browser, connect Phantom, play.
- [b]A real game[/b] - authoritative servers, real-time combat, meaningful progression.
- [b]You own your account[/b] - your wallet is the key; no company controls your login.
- [b]Social by default[/b] - parties, guilds, emotes, world chat.[/indent]

[font_size=20][b][color=#e7b26a]3. The World[/color][/b][/font_size]
A hand-crafted pixel-art realm of dungeons, wilds, and townships. Explore shared persistent worlds, fight monsters, take NPC quests, gather and craft, climb leaderboards, and band together in guilds and parties.

[font_size=20][b][color=#e7b26a]4. Core Gameplay[/color][/b][/font_size]
[indent]- [b]Real-time combat[/b] - weapon abilities, telegraphed enemy attacks, dungeon & world bosses.
- [b]Progression[/b] - XP from mobs, quests, dailies; each level grants attribute points and a power bump. Hit the cap for the [b]"Ascendant"[/b] title.
- [b]Three tracks[/b] - character level, weapon mastery trees, and profession skills (mining, smithing, tailoring, leatherworking, harvesting).
- [b]Dungeons[/b] - co-op instances, Normal/Hard, shared revives, fastest-clear boards.
- [b]Guilds & territory[/b] - found a guild, capture banners, earn Glory.
- [b]Parties & social[/b] - party chat, ally bars, emotes (/wave, /dance), sit anywhere, spectator fireball mode.[/indent]

[font_size=20][b][color=#e7b26a]5. Multiplayer Architecture[/color][/b][/font_size]
A true server-authoritative MMO: a [b]master[/b] server (accounts/auth/registry), a [b]gateway[/b] (public HTTP edge: wallet challenge/verify, sessions), and parallel [b]world[/b] servers running the simulation. Clients connect over [b]WebSocket[/b], so the same game runs in a browser and natively. All game-critical logic is server-side - the client renders and predicts; the server decides.

[font_size=20][b][color=#e7b26a]6. Wallet & Identity (Sign-In With Solana)[/color][/b][/font_size]
[indent]- [b]No custody[/b] - Mythreach never holds your keys or funds.
- [b]The flow[/b] - connect Phantom -> server issues a single-use nonce -> you sign it -> server verifies the [b]ed25519[/b] signature against your public key. The wallet address IS the account.
- [b]Anti-replay[/b] - nonces are one-shot and time-limited.
- [b]Verified, not trusted[/b] - verification runs server-side (RFC 8032 validated).[/indent]

[font_size=20][b][color=#e7b26a]7. Economy & Token (Planned)[/color][/b][/font_size]
The alpha uses off-chain in-game gold. The roadmap adds on-chain layers only where they add value:
[indent]- [b]$MYTH token (planned)[/b] - utility for cosmetics, marketplace fees, seasonal rewards. Not yet live.
- [b]Player marketplace (planned)[/b] - peer-to-peer trades settled via your wallet.
- [b]Asset ownership (planned)[/b] - select cosmetics/characters mintable as Solana NFTs.
- [b]No pay-to-win[/b] - on-chain value targets cosmetics & the economy, never raw combat power.[/indent]
[i]Tokenomics are under design and will ship in a dedicated economics paper before any token exists. Nothing here is an offer or a promise of return.[/i]

[font_size=20][b][color=#e7b26a]8. Security & Fair Play[/color][/b][/font_size]
Server-authoritative simulation, ed25519 wallet verification with single-use nonces, rate-limited auth/chat. Roadmap: movement anti-cheat and area-of-interest networking.

[font_size=20][b][color=#e7b26a]9. Roadmap[/color][/b][/font_size]
[indent]- [b]Now (Alpha)[/b] - wallet login, real-time combat, leveling, parties, guilds, dungeons, web build.
- [b]Next[/b] - mana/stamina economy, entity interpolation, anti-cheat, private instances, onboarding.
- [b]Later[/b] - marketplace, $MYTH token, on-chain cosmetics, seasons & ranked, mobile.[/indent]

[font_size=20][b][color=#e7b26a]10. Disclaimer[/color][/b][/font_size]
[color=#b9b4a8]Mythreach is in active alpha; features and timelines may change. This document is informational only and is NOT investment advice, a securities offering, or a guarantee of any token, asset, or financial outcome. Connecting a wallet never transfers custody of your funds.[/color]

[color=#7a756b]Mythreach - (c) Mythreach Studio - Alpha[/color]"""
