// Usage of Calculator

import { Calculator, processNumbers, MAGIC_NUMBER } from './example.js';

function main() {
  const calc = new Calculator();

  const sum = calc.add(10, 20);
  console.log('Sum:', sum);

  const diff = calc.subtract(100, MAGIC_NUMBER);
  console.log('Difference:', diff);

  const product = calc.multiply(5, 8);
  console.log('Product:', product);

  const numbers = [1, 2, 3, 4, 5];
  const total = processNumbers(numbers);
  console.log('Total:', total);
}

// Another Calculator instance
const globalCalc = new Calculator();

main();