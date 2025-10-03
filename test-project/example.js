// Example JavaScript file

class Calculator {
  constructor() {
    this.result = 0;
  }

  add(a, b) {
    return a + b;
  }

  subtract(a, b) {
    return a - b;
  }

  multiply(a, b) {
    return a * b;
  }
}

function processNumbers(nums) {
  const calc = new Calculator();
  return nums.reduce((acc, num) => calc.add(acc, num), 0);
}

const MAGIC_NUMBER = 42;

export { Calculator, processNumbers, MAGIC_NUMBER };