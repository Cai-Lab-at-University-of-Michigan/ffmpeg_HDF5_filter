import unittest
from colorama import Fore, Back, Style
from tabulate import tabulate

class ColoredTestResult(unittest.TextTestResult):
    """Custom test result class that colorizes the output."""
    
    def addSuccess(self, test):
        super().addSuccess(test)
        self.stream.writeln(f"{Fore.GREEN}✓ {test.shortDescription() or str(test)}{Style.RESET_ALL}")
    
    def addError(self, test, err):
        super().addError(test, err)
        self.stream.writeln(f"{Fore.RED}✗ ERROR: {test.shortDescription() or str(test)}{Style.RESET_ALL}")
        
    def addFailure(self, test, err):
        super().addFailure(test, err)
        self.stream.writeln(f"{Fore.RED}✗ FAIL: {test.shortDescription() or str(test)}{Style.RESET_ALL}")
        
    def addSkip(self, test, reason):
        super().addSkip(test, reason)
        self.stream.writeln(f"{Fore.YELLOW}⚠ SKIP: {test.shortDescription() or str(test)} ({reason}){Style.RESET_ALL}")

class ColoredTestRunner(unittest.TextTestRunner):
    """Custom test runner that uses the ColoredTestResult class."""
    resultclass = ColoredTestResult

def print_summary(name, result):
    """Print a colorized summary of test results."""
    print(f"\n{Back.CYAN}{Fore.BLACK}{Style.BRIGHT} {name} SUMMARY {Style.RESET_ALL}")
    print(f"{Fore.CYAN}{'═' * 60}{Style.RESET_ALL}")
    
    # Count results
    total = result.testsRun
    failed = len(result.failures)
    errors = len(result.errors)
    skipped = len(result.skipped)
    passed = total - failed - errors - skipped
    
    # Calculate percentages
    pass_percent = (passed / total) * 100 if total > 0 else 0
    
    # Determine overall status color
    if failed > 0 or errors > 0:
        status_color = Fore.RED
        status_text = "FAILED"
    else:
        status_color = Fore.GREEN
        status_text = "PASSED"
    
    # Print counts with colors
    print(f"Total tests: {total}")
    print(f"  {Fore.GREEN}✓ Passed: {passed} ({pass_percent:.1f}%){Style.RESET_ALL}")
    if failed > 0:
        print(f"  {Fore.RED}✗ Failed: {failed}{Style.RESET_ALL}")
    if errors > 0:
        print(f"  {Fore.RED}✗ Errors: {errors}{Style.RESET_ALL}")
    if skipped > 0:
        print(f"  {Fore.YELLOW}⚠ Skipped: {skipped}{Style.RESET_ALL}")
    
    # Print overall status
    print(f"{Fore.CYAN}{'─' * 60}{Style.RESET_ALL}")
    print(f"Overall status: {status_color}{Style.BRIGHT}{status_text}{Style.RESET_ALL}")
    print(f"{Fore.CYAN}{'═' * 60}{Style.RESET_ALL}")