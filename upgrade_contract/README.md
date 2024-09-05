# Jungle Run Contract Upgrade
This project will be used to upgrade ``jungle_run`` aptos module 

## Usage

1. Choose network in ``index.ts`` file 
```shell
const network = 'TESTNET'
```
2. Add contract address in ``contract.ts`` file under relevant network
```txt
TESTNET: {  # this must be under your relevant network
    jungle_run: "# your contract address here", 
}
```
3. Add your private key in ``.env`` file under relevant network this private key must have admin right to this contract 
```txt
APTOS_TESTNET='# your private key here without starting 0x'
```
4. Run below command to upgrade your package 
```shell
$ npm run start
```
5. Please note that I have setup this project to upgrade contract in the parallel directory if you want to use it to upgrade other smart contracts you must look into ```getContractDirectory()``` method in ```buildPackage.ts``` file
