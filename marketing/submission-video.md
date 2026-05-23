# submission video script

3-minute walkthrough for the agora submission. Every frame either shows on-chain state or autonomous-agent action. No human-signing visible after the opening receipt.

## Constraints

- One persona on camera or in voiceover. Handle: `adiled`. EU AI Act Article 50 disclosure embedded in the closing frame.
- Receipt frames are real settled tx hashes from the operator and the dispute escrow. Numbers on screen are the same numbers the dashboard shows, fetched live, not screenshotted from a build artifact.
- No company names other than the upstream open-source projects referenced (`circlefin/refund-protocol`, `OpenZeppelin`, `viem`, `alloy`).
- No comparative framing against any peer-chain or peer-operator. The chain choice is named once: "on Arc, because USDC, EURC, and FxEscrow cohabit there."

## Timestamp script

| timestamp | frame | voiceover |
|---|---|---|
| 0:00 - 0:05 | Receipt-image: settled-fill tx on Arc with hash visible. Cumulative volume number top-right. | "Real fills, real volume, real on-chain. Here is the latest." |
| 0:05 - 0:30 | Three-pane split: market-creation agent posts a new question on screen, resolver agent fetches a release and posts a resolution claim, dispute agent receives a synthetic challenge and routes it to escrow. No human signing on screen. | "Three autonomous loops. Markets are created against scheduled releases without prompting. Resolutions fire from the data the moment it lands. Disputes route to a primitive that holds collateral until an arbiter rules." |
| 0:30 - 1:30 | End-to-end dispute demo. A market is resolved against the propose-then-challenge path. A challenger posts a bond. The arbiter rules. Bond returns to treasury. Winning shares redeem. Every transition shows its tx hash. | "The dispute primitive is forked from circlefin's open-source refund-protocol with four classes of correctness fix applied. The challenger's bond lives in the escrow contract, not in the operator. The arbiter rules through a separate transaction. The procedural shape mirrors a chargeback dispute lifecycle and an institutional arbitration framework, both of which the buyer set already operates inside." |
| 1:30 - 2:50 | Live dashboard. Three numbers against the day-1 public commitment: transactions on Arc, notional in USDC, unique non-team wallets. Tier label visible (breakout / strong / credible). | "We committed publicly on day one. The dashboard tracks against that commitment in real time. Every fill, every wallet, every settlement is on-chain and verifiable." |
| 2:50 - 3:00 | Single still: project repo URL, dashboard URL, EU AI Act Article 50 disclosure, persona handle. | "Open repository. Open dashboard. Built and operated by an AI agent under EU AI Act Article 50." |

## Recording checklist

- All tx hashes shown on screen are reachable on the operator network's block explorer at video-publish time.
- Dashboard frame in 1:30 - 2:50 has the three numbers fetched live from on-chain state, not from a snapshot file.
- Voiceover script reviewed for AGENTS.md `Information hygiene` (no actor names, no citation URLs from research, no strategic framing language from gitignored docs).
- Video file uploaded to a host that does not require account creation by the viewer to play (mp4 on the project domain or an unlisted youtube link in the repo footer).

## Receipt-image template

Standalone image fired within five minutes of each in-window macro event. Same template each event so the visual is recognizable across the cohort.

Layout, top to bottom:

1. Top bar: project handle (`adiled`), event name and time (e.g. "CPI April 2026 release, 8:30 ET"), block height of the settling tx.
2. Hero number: the resolved value (e.g. "CPI YoY = 3.256%").
3. Resolution row: question hash short prefix, derived outcome (`YES` or `NO`), winning side payout in USDC.
4. Verification row: settling tx hash (full, monospace), link target to the operator network explorer.
5. Footer: EU AI Act Article 50 disclosure and the project repository URL.

The receipt is generated from on-chain data by the resolver agent's post-settlement hook. No human composes it.

## What the video does not include

- No team headshots, no on-camera narrator. Persona is `adiled`; the persona has no face by design.
- No comparative "we built faster than X" framing.
- No screenshots from the strategy folders, the commanding-database dotfiles, or the actor maps. Those live behind the gitignore boundary.
- No URLs that require login or a paid tier to view.
