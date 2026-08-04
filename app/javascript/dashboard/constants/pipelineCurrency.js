export const SUPPORTED_PIPELINE_CURRENCIES = ['usd', 'brl'];
export const DEFAULT_PIPELINE_CURRENCY = 'usd';

export const getCurrencyConfig = currency => {
  const configs = {
    usd: { code: 'USD', display: 'symbol', fractionDigits: 0 },
    brl: { code: 'BRL', display: 'symbol', fractionDigits: 2 },
  };
  return configs[currency] || configs[DEFAULT_PIPELINE_CURRENCY];
};

export const formatCurrencyAmount = (
  amount,
  currency = DEFAULT_PIPELINE_CURRENCY,
  compact = false
) => {
  const config = getCurrencyConfig(currency);
  const options = {
    style: 'currency',
    currency: config.code,
    currencyDisplay: config.display,
    minimumFractionDigits: compact ? 0 : config.fractionDigits,
    maximumFractionDigits: compact ? 1 : config.fractionDigits,
  };

  if (compact) {
    options.notation = 'compact';
    options.compactDisplay = 'short';
  }

  const formatter = new Intl.NumberFormat('en-US', options);
  return formatter.format(amount);
};
