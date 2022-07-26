PredyV3
=====


'''
forge test --match-path test/BorrowLPT.t.sol --fork-url https://mainnet.infura.io/v3/2b60820a2ed6453e9be6dde1178c8203 --fork-block-number 15180000 -vvvvv
forge test --match-path test/PricingModule2.t.sol --fork-url https://mainnet.infura.io/v3/2b60820a2ed6453e9be6dde1178c8203 --fork-block-number 15180000 -vvvvv
'''


* テストを綺麗にする
* wrapなどを使用する。
* できるだけprimitiveな要素に切り分け、デプロイする。
* Strategyごとにイベントを追加する
* BorrowLptに、call, put以外のneutralを追加する