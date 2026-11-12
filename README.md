# Weir Disperse

`src/Disperse.sol`: pays many recipients one ERC-20 in a single transaction on Robinhood Chain (chain id 4663,
Arbitrum Orbit). The Weir app uses it to pay several contest winners at once from the admin's own wallet, in USDG,
WEIR, IMD, WETH or any other plain ERC-20. The product never holds the money: funds move straight from the caller
to each recipient.

The source is byte-for-byte the `Disperse` already live on Base and Base Sepolia at
`0x320418D854f3eD0E59e691dD7c767A22B8E5C9E9` (pay-usdc). Nothing in it is chain or token specific.

**Not audited.** Tests and a swarm review are not an audit.

## Contract

- `disperse(token, to[], amounts[])`: `transferFrom(msg.sender → to[i], amounts[i])` for every row. Needs a prior
  approval of at least the sum.
- `disperseWithPermit(token, to[], amounts[], deadline, v, r, s)`: same, with an EIP-2612 permit for exactly the
  sum. `permit` is wrapped in `try/catch`, so a front-run replay of the signature cannot block the send; the
  allowance check afterwards is the real gate. When the permit fails AND the allowance is short, the permit's own
  revert reason is bubbled. On a token without `permit`, pass zeros and approve first.
- `sumOf(to[], amounts[])`: view helper, same validation, returns the total.
- Reverts: `Empty`, `LengthMismatch`, `ZeroRecipient(i)`, `SelfRecipient(i)` (the Disperse contract itself),
  `ZeroAmount(i)`, `InsufficientAllowance(needed, have)`.
- One event per call: `Dispersed(sender, token, total, count)`. Per-recipient detail is in the token's own
  `Transfer` logs, each with `from` = the caller, which is what the app's payout check reads.

Properties: no constructor arguments, no owner, no fee, no pause, no upgrade, no rescue, no storage. The contract
never holds tokens, so reentrancy cannot move anything the caller did not already approve. Fee-on-transfer and
rebasing tokens are unsupported and undetected. A batch is atomic: one recipient the token refuses (a frozen USDG
address, for example) reverts the whole call and nothing moves.

## Tokens on Robinhood Chain (checked on a fork, 2026-11-11)

| token | address | decimals | permit |
|---|---|---|---|
| USDG (Paxos Global Dollar) | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | 6 | yes, EIP-2612: `disperseWithPermit` works in one transaction |
| WEIR | `0x58b82fa656ecf47a0dca5be6bad06b92e22f7dbe` | 18 | no: approve, then `disperse` |

Gas with real USDG: about 33,700 per fresh-balance recipient, so 250 recipients is about 8.4M. The app caps a batch
at 250 and splits larger lists.

## Build and test

```sh
forge build
forge test
forge fmt --check
# fork tests against real USDG and WEIR; skipped when the variable is unset
RH_RPC_URL=https://robinhood-rpc.publicnode.com forge test --match-contract DisperseForkTest -vv
```

30 tests: 25 unit and fuzz (mocks for a 6-decimals permit token, a no-return token, a plain token and a reentrant
token) and 5 fork tests. `foundry.toml`, verbatim:

```toml
[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
solc = "0.8.26"
optimizer = true
optimizer_runs = 200
evm_version = "cancun"
via_ir = false
bytecode_hash = "none"
fs_permissions = []

[fuzz]
runs = 256

[profile.ci.fuzz]
runs = 2000

[rpc_endpoints]
robinhood = "${RH_RPC_URL}"
```

Dependencies are vendored under `lib/`: OpenZeppelin Contracts v5.5.0 and forge-std.

## Deploy

The IMD swarm deploys it from `launch.json` (kind `evm_contracts`, chain 4663, contract `Disperse`, no constructor
arguments) after auditing the repository as it arrived; the request is `docs/imd/launch-disperse-robinhood.json`
in the app repo. This folder is pushed to `weircool/disperse-contracts` as a subtree for that, as Townies is.

`script/Deploy.s.sol` is the owner's fallback: a deterministic CREATE2 deploy through the standard proxy at
`0x4e59b44847b379578588920cA78FbF26c0B4956C` (present on Robinhood Chain) that lands at the Base address
`0x320418D854f3eD0E59e691dD7c767A22B8E5C9E9`, refuses to broadcast if the bytecode drifted and skips when the
address already has code. A swarm deployment lands at the swarm deployer's own address instead; either works.

## After deployment

Record the address here and in the app (`src/lib/robinhoodChain.ts`), and write the ABI for the app with
`forge inspect src/Disperse.sol:Disperse abi --json`.
