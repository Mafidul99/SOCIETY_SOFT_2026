Map<String, double> calculateFlatLoan({
  required double principal,
  required double annualRate,
  required int tenureYears,
}) {
  final interest =
      (principal * annualRate / 100 * tenureYears * 100).round() / 100;
  final total = ((principal + interest) * 100).round() / 100;
  final monthly = (total / (tenureYears * 12) * 100).round() / 100;
  return {
    'totalInterest': interest,
    'totalPayable': total,
    'monthlyInstallment': monthly,
  };
}

Map<String, double> calculateInterestOnlyLoan({
  required double principal,
  required double annualRate,
  required int tenureYears,
}) {
  final interest =
      (principal * annualRate / 100 * tenureYears * 100).round() / 100;
  final total = ((principal + interest) * 100).round() / 100;
  final monthly = (interest / (tenureYears * 12) * 100).round() / 100;
  return {
    'totalInterest': interest,
    'totalPayable': total,
    'monthlyInstallment': monthly,
  };
}

Map<String, double> calculateLoanRepayment({
  required double principal,
  required double annualRate,
  required int tenureYears,
  required String calculationMethod,
}) {
  if (calculationMethod == 'interest_only') {
    return calculateInterestOnlyLoan(
      principal: principal,
      annualRate: annualRate,
      tenureYears: tenureYears,
    );
  }
  return calculateFlatLoan(
    principal: principal,
    annualRate: annualRate,
    tenureYears: tenureYears,
  );
}

String loanCalculationMethodLabel(String method) =>
    method == 'interest_only' ? 'Interest only' : 'Fixed EMI';
