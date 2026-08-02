const camelcaseKeys = require('camelcase-keys');
const arr = [{ a_b: 1 }, { c_d: 2 }];
try {
  console.log(arr.map(camelcaseKeys));
} catch (e) {
  console.log(e);
}
