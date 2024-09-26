import { callEntryFunc } from './helper/aptos';
import {
  buildPackage,
  getContractDirectory,
  serializePackage,
} from './helper/buildPackage';

import * as dotenv from 'dotenv';
dotenv.config();

const network = 'TESTNET';

(async () => {
  try {
    const contract = process.env.APTOS_CONTRACT_ADDRESS;
    const contractModuleName = process.env.APTOS_CONTRACT_MODULE_NAME;
    const packageBuild = buildPackage(getContractDirectory());
    console.log('Package build successfully.');
    const serialized = serializePackage(packageBuild);
    console.log('Package serialized successfully.');
    const hash = await callEntryFunc(
      network,
      `${contract}::${contractModuleName}`,
      'upgrade_contract',
      [],
      [serialized.meta, serialized.bytecodes],
    );
    console.log('Deployed:', packageBuild.mv_files);
    console.log('Tx hash', hash);
  } catch (e) {
    console.log(e);
  }
  // `text` is not available here
})();
