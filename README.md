## NFGho

**NFGho is a [Facilitator](https://docs.gho.xyz/concepts/how-gho-works/gho-facilitators) for [GHO](https://docs.gho.xyz/)**

NFGho lets anyone use their idle NFTs to mint GHO tokens. Additionally, if time permits GHO tokens can be directly swapped for USDC/USDT via the [GHO Stability Module (GSM)](https://governance.aave.com/t/gho-stability-module-update/14442), which can then be supplied to [Aave](https://aave.com/) to generate yield.

Thus NFGho lets you utilize your idle NFTs to generate liquidity to generate yield or use elsewhere in DeFi.

NFGho is an evolution of a previous project of mine called [YieldNFT](https://bit.ly/YieldNFT) and a twist on CDP-based stablecoin, although the GHO is the stablecoin here.

NFGho will use Chainlink's [NFT Floor Price Feeds](https://docs.chain.link/data-feeds/nft-floor-price) to determine the value of the NFTs being used as collateral.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

