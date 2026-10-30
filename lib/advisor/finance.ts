/**
 * Investment arithmetic for the advisor.
 *
 * The model chooses the inputs and explains them; this does the sums, because
 * a language model doing compound interest in its head is how a yield of 5.8%
 * becomes 8.5%. Nothing here knows any Jordanian rate, fee or tax: every
 * input that depends on one (purchase costs, interest, growth) arrives from
 * the conversation, and anything not supplied is reported as not included
 * rather than filled with a default.
 */

export type InvestmentInput = {
  price: number;
  monthlyRent: number | null;
  nightlyRate: number | null;
  occupancyPct: number | null;
  annualCosts: number | null;
  vacancyPct: number | null;
  purchaseCostsPct: number | null;
  downPaymentPct: number | null;
  loanRatePct: number | null;
  loanYears: number | null;
  growthPct: number | null;
  horizonYears: number | null;
};

const round = (n: number, dp = 0) => {
  const f = 10 ** dp;
  return Math.round(n * f) / f;
};

/** Level monthly payment on an amortising loan. Zero interest is just the principal spread out. */
export function monthlyPayment(principal: number, annualRatePct: number, years: number): number {
  const m = years * 12;
  if (m <= 0) return 0;
  const r = annualRatePct / 100 / 12;
  if (r === 0) return principal / m;
  return (principal * r) / (1 - (1 + r) ** -m);
}

export function analyse(i: InvestmentInput) {
  const notes: string[] = [];
  const P = i.price;

  // Income: a monthly let, or nightly letting at an occupancy rate. Never both.
  let grossRent: number | null = null;
  if (i.monthlyRent != null) {
    grossRent = i.monthlyRent * 12;
  } else if (i.nightlyRate != null) {
    if (i.occupancyPct == null) notes.push("Nightly rate given without an occupancy rate: rental income not calculated.");
    else grossRent = i.nightlyRate * 365 * (i.occupancyPct / 100);
  } else {
    notes.push("No rent supplied: income figures not calculated.");
  }

  const vacancy = i.vacancyPct ?? 0;
  if (grossRent != null && i.vacancyPct == null && i.monthlyRent != null) notes.push("No vacancy allowance applied.");
  const costs = i.annualCosts ?? 0;
  if (grossRent != null && i.annualCosts == null) notes.push("No running costs supplied (service charges, maintenance, management, insurance): net figures are overstated.");
  const buyCostsPct = i.purchaseCostsPct ?? 0;
  if (i.purchaseCostsPct == null) notes.push("Purchase costs (registration fees, taxes, agent) not included.");

  const acquisition = P * (1 + buyCostsPct / 100);
  const effectiveRent = grossRent != null ? grossRent * (1 - vacancy / 100) : null;
  const noi = effectiveRent != null ? effectiveRent - costs : null;

  const income =
    grossRent == null
      ? null
      : {
          gross_annual_rent_jod: round(grossRent),
          effective_annual_rent_jod: round(effectiveRent as number),
          net_operating_income_jod: round(noi as number),
          gross_yield_pct: round((grossRent / P) * 100, 2),
          net_yield_pct: round(((noi as number) / acquisition) * 100, 2),
          payback_years: (noi as number) > 0 ? round(acquisition / (noi as number), 1) : null,
        };

  // Financing, only when all three terms are known.
  let financing = null;
  if (i.downPaymentPct != null && i.loanRatePct != null && i.loanYears != null) {
    const loan = P * (1 - i.downPaymentPct / 100);
    const pay = monthlyPayment(loan, i.loanRatePct, i.loanYears);
    const cashIn = P * (i.downPaymentPct / 100) + P * (buyCostsPct / 100);
    const debtService = pay * 12;
    const cashFlow = noi != null ? noi - debtService : null;
    financing = {
      loan_jod: round(loan),
      monthly_payment_jod: round(pay),
      total_interest_jod: round(pay * i.loanYears * 12 - loan),
      cash_invested_jod: round(cashIn),
      annual_cash_flow_jod: cashFlow != null ? round(cashFlow) : null,
      cash_on_cash_pct: cashFlow != null && cashIn > 0 ? round((cashFlow / cashIn) * 100, 2) : null,
    };
  } else if (i.downPaymentPct != null || i.loanRatePct != null || i.loanYears != null) {
    notes.push("Financing needs a down payment, an interest rate and a term: not calculated.");
  }

  // A scenario, labelled as one. Growth is the caller's assumption.
  let scenario = null;
  if (i.growthPct != null && i.horizonYears != null) {
    const value = P * (1 + i.growthPct / 100) ** i.horizonYears;
    scenario = {
      assumed_annual_growth_pct: i.growthPct,
      years: i.horizonYears,
      value_at_end_jod: round(value),
      value_change_jod: round(value - P),
      cumulative_net_income_jod: noi != null ? round(noi * i.horizonYears) : null,
      label: "Scenario under the stated growth assumption, not a forecast.",
    };
  }

  return {
    inputs: {
      price_jod: P,
      monthly_rent_jod: i.monthlyRent,
      nightly_rate_jod: i.nightlyRate,
      occupancy_pct: i.occupancyPct,
      annual_running_costs_jod: i.annualCosts,
      vacancy_pct: i.vacancyPct,
      purchase_costs_pct: i.purchaseCostsPct,
    },
    acquisition_cost_jod: round(acquisition),
    income,
    financing,
    scenario,
    not_included: notes,
  };
}
