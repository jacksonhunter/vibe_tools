// Test file with internal references

class Calculator {
  constructor() {
    this.result = 0;
  }

  add(a, b) {
    this.result = a + b;
    return this.result;
  }

  subtract(a, b) {
    this.result = a - b;
    return this.result;
  }

  calculate(operation, a, b) {
    if (operation === 'add') {
      return this.add(a, b);  // Internal reference to add method
    } else if (operation === 'subtract') {
      return this.subtract(a, b);  // Internal reference to subtract method
    }
    return this.result;
  }

  clear() {
    this.result = 0;
  }
}

function testCalculator() {
  const calc = new Calculator();  // Internal reference to Calculator class
  calc.add(5, 3);  // Internal reference to add method
  calc.subtract(10, 4);  // Internal reference to subtract method
  console.log(calc.result);
}

// Self-test
testCalculator();  // Internal reference to function