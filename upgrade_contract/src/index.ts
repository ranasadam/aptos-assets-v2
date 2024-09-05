import { callEntryFunc } from './helper/aptos';
import {
  buildPackage,
  getContractDirectory,
  serializePackage,
} from './helper/buildPackage';
import { CONTRACTS } from './const';

const network = 'TESTNET';

const contract = CONTRACTS[network]['jungle_run'];

(async () => {
  try {
    const packageBuild = buildPackage(getContractDirectory());
    console.log('Package build successfully.');
    const serialized = serializePackage(packageBuild);
    console.log('Package serialized successfully.');
    const hash = await callEntryFunc(
      network,
      `${contract}::assets`,
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
