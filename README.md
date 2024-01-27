## NFGho

**NFGho is a [Facilitator](https://docs.gho.xyz/concepts/how-gho-works/gho-facilitators) for [GHO](https://docs.gho.xyz/)**

NFGho lets anyone use their idle NFTs to mint GHO tokens. Additionally, ~~if time permits~~ GHO tokens can be directly swapped for USDC/USDT via the [GHO Stability Module (GSM)](https://governance.aave.com/t/gho-stability-module-update/14442), which can then be supplied to [Aave](https://aave.com/) to generate yield.

NFGho lets you utilize your idle NFTs to generate liquidity to generate yield or use elsewhere in DeFi.

NFGho is an evolution of a previous project of mine called [YieldNFT](https://bit.ly/YieldNFT) and a twist on CDP-based stablecoin, although the GHO is the stablecoin here.

NFGho uses Chainlink's [NFT Floor Price Feeds](https://docs.chain.link/data-feeds/nft-floor-price) to determine the value of the NFTs being used as collateral.

### How it works

1. User deposits NFTs into the NFGho contract
2. NFGho contract mints GHO tokens as debt for the user against the NFTs
   1. Chainlink's NFT Floor Price Feeds are used to determine the value of the NFTs and thus the health factor of the position
3. User can burn GHO tokens to repay the debt and withdraw their NFTs
4. User can redeem their NFTs by paying back the debt
5. User's NFTs can be liquidated if the health factor falls below 1.0
6. User can use the GHO tokens to mint USDC via the GSM
7. User can directly supply the USDC to Aave to generate yield

### Potential Challenges

- Liquidation of NFTs might require liquidating the entire position, by burning the total amount of debt and liquidator will receive the entire NFT. This is because NFTs are indivisible. We could look into fractionalizing NFTs to solve this problem. NFTfi, NFTX, Fractional, etc. can be explored
- Different tokenIds of the same collection is considered fungible for now, since we're using floor price to calculate value. This may not be the best UX, but it's a start

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### TODO

- [ ] More tests for liquidation & health factor
- [ ] Refactors to avoid code duplication
- [ ] Generalize handling precision & decimals
- [ ] Tests with multiple collections
- [ ] Fuzz tests & Invariant tests