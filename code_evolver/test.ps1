function Test-Function {
    Write-Host 'Hello World'
}

function Get-Data {
    param($Path)
    return Get-Content $Path
}

class TestClass {
    [string]$Name

    TestClass([string]$name) {
        $this.Name = $name
    }

    [void] Display() {
        Write-Host $this.Name
    }
}

$GlobalVar = "Test"