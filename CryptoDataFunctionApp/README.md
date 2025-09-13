# Cryptocurrency Data Azure Function

A PowerShell-based Azure Function that provides real-time cryptocurrency data from the CoinGecko API. This function can retrieve current prices, market data, and rankings for individual cryptocurrencies or lists of top cryptocurrencies in multiple currencies.

## What This Project Does

This Azure Function serves as a REST API that:

- **Fetches cryptocurrency prices** for any coin supported by CoinGecko (Bitcoin, Ethereum, etc.)
- **Retrieves top cryptocurrency lists** ranked by market capitalization
- **Supports multiple currencies** (USD, EUR, GBP, JPY, and more)
- **Handles rate limiting** automatically with retry logic
- **Validates input parameters** and provides clear error messages
- **Returns structured JSON responses** that are easy to parse and use

### Example Use Cases

- Building a cryptocurrency portfolio tracker
- Creating price alert systems
- Integrating crypto data into dashboards
- Educational projects about financial APIs
- Market research and analysis tools

## Prerequisites

Before you begin, make sure you have the following installed:

### Required Software

1. **Azure Functions Core Tools** (version 4.x)
   - Download from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local
   - This allows you to run Azure Functions locally

2. **PowerShell** (version 7.2 or higher)
   - Download from: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell
   - Required to run PowerShell-based Azure Functions

3. **curl** (for testing)
   - Usually pre-installed on macOS and Linux
   - Windows users can use PowerShell's `Invoke-RestMethod` instead

### Optional but Recommended

4. **jq** (for JSON processing in tests)
   - Install on macOS: `brew install jq`
   - Install on Ubuntu: `sudo apt-get install jq`
   - Install on Windows: Download from https://jqlang.github.io/jq/

5. **Visual Studio Code** (for editing)
   - Download from: https://code.visualstudio.com/
   - Install the Azure Functions extension for better development experience

## Project Structure

```
CryptoDataFunctionApp/
├── CryptoDataFunction/          # Main function folder
│   ├── function.json           # Function configuration
│   └── run.ps1                # Main PowerShell code
├── host.json                   # Host configuration
├── local.settings.example.json # Example local development settings
├── profile.ps1               # PowerShell profile for cold starts
├── requirements.psd1          # PowerShell module dependencies
├── test_crypto_function_clean.sh  # Test script
├── .gitignore                 # Git ignore rules
└── README.md                  # This documentation
```

## Getting Started

### Step 1: Clone or Download the Project

If you have git installed:
```bash
git clone <repository-url>
cd CryptoDataFunctionApp
```

Or download the files manually and place them in a folder called `CryptoDataFunctionApp`.

### Step 2: Verify Your Installation

Open a terminal/command prompt and verify the required tools are installed:

```bash
# Check Azure Functions Core Tools
func --version

# Check PowerShell version
pwsh --version
```

You should see version numbers returned. If you get "command not found" errors, you need to install the missing tools.

### Step 3: Configure Local Settings

Set up your local development configuration:

1. **Copy the example settings file:**
   ```bash
   cp local.settings.example.json local.settings.json
   ```

2. **Modify settings as needed for your environment:**
   - The default settings should work for most local development
   - You can change the port number if 7071 is already in use
   - Add any additional configuration variables you might need

The `local.settings.json` file is excluded from git to prevent accidentally committing sensitive configuration data.

**Example `local.settings.example.json` content:**
```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "powershell",
    "FUNCTIONS_WORKER_RUNTIME_VERSION": "7.2"
  },
  "Host": {
    "LocalHttpPort": 7071,
    "CORS": "*"
  }
}
```

### Step 4: Start the Function Locally

Navigate to your project folder and start the function:

```bash
cd CryptoDataFunctionApp
func start
```

You should see output similar to:
```
Azure Functions Core Tools
Core Tools Version: 4.2.2
Function Runtime Version: 4.104.1

Functions:
        CryptoDataFunction: [GET,POST] http://localhost:7071/api/CryptoDataFunction
```

**Important**: Keep this terminal window open. The function is now running locally.

### Step 5: Test the Function

Open a new terminal window and test the function:

#### Quick Test (using curl)
```bash
# Test basic functionality
curl "http://localhost:7071/api/CryptoDataFunction?action=top&limit=3"

# Test Bitcoin price
curl "http://localhost:7071/api/CryptoDataFunction?action=coin&coin=bitcoin"
```

#### Comprehensive Test (using the test script)
```bash
# Make the test script executable (macOS/Linux)
chmod +x test_crypto_function_clean.sh

# Run basic tests
./test_crypto_function_clean.sh http://localhost:7071/api/CryptoDataFunction

# Run quick tests (5-second delays)
./test_crypto_function_clean.sh http://localhost:7071/api/CryptoDataFunction --quick

# Run extended tests
./test_crypto_function_clean.sh http://localhost:7071/api/CryptoDataFunction --extended

# Run with debug information
./test_crypto_function_clean.sh http://localhost:7071/api/CryptoDataFunction --debug
```

## API Documentation

### Base URL
When running locally: `http://localhost:7071/api/CryptoDataFunction`

### Supported HTTP Methods
- **GET**: Parameters in query string
- **POST**: Parameters in JSON body

### Parameters

| Parameter | Required | Default | Description | Example Values |
|-----------|----------|---------|-------------|----------------|
| `action` | No | `top` | Type of data to retrieve | `top`, `coin` |
| `coin` | Yes (if action=coin) | - | Cryptocurrency ID | `bitcoin`, `ethereum`, `cardano` |
| `currency` | No | `usd` | Currency for prices | `usd`, `eur`, `gbp`, `jpy` |
| `limit` | No | `10` | Number of coins (for top action) | `1` to `250` |

### API Endpoints

#### 1. Get Top Cryptocurrencies

**Request:**
```
GET /api/CryptoDataFunction?action=top&limit=5&currency=usd
```

**Response:**
```json
{
  "success": true,
  "timestamp": "2025-09-13T01:30:00Z",
  "data": {
    "currency": "USD",
    "total_results": 5,
    "results": [
      {
        "id": "bitcoin",
        "name": "Bitcoin",
        "symbol": "BTC",
        "current_price": 45000,
        "market_cap": 850000000000,
        "market_cap_rank": 1,
        "price_change_percentage_24h": 2.5
      }
    ]
  },
  "source": "CoinGecko API v3"
}
```

#### 2. Get Individual Cryptocurrency

**Request:**
```
GET /api/CryptoDataFunction?action=coin&coin=bitcoin&currency=usd
```

**Response:**
```json
{
  "success": true,
  "timestamp": "2025-09-13T01:30:00Z",
  "data": {
    "id": "bitcoin",
    "name": "Bitcoin",
    "symbol": "BTC",
    "current_price": 45000,
    "market_cap": 850000000000,
    "market_cap_rank": 1,
    "price_change_24h": 1000,
    "price_change_percentage_24h": 2.5,
    "circulating_supply": 19500000,
    "total_supply": 19500000,
    "max_supply": 21000000
  },
  "source": "CoinGecko API v3"
}
```

#### 3. Error Response

**Request:**
```
GET /api/CryptoDataFunction?action=coin
```

**Response:**
```json
{
  "success": false,
  "error": "Coin parameter is required when action is 'coin'",
  "timestamp": "2025-09-13T01:30:00Z",
  "request_info": {
    "action": "coin",
    "currency": "usd",
    "coin_id": "",
    "limit": "10"
  }
}
```

### Example Requests

#### Using curl (Command Line)
```bash
# Top 10 cryptocurrencies in USD
curl "http://localhost:7071/api/CryptoDataFunction?action=top&limit=10&currency=usd"

# Bitcoin price in EUR
curl "http://localhost:7071/api/CryptoDataFunction?action=coin&coin=bitcoin&currency=eur"

# Ethereum data
curl "http://localhost:7071/api/CryptoDataFunction?action=coin&coin=ethereum"

# Top 5 coins in Japanese Yen
curl "http://localhost:7071/api/CryptoDataFunction?action=top&limit=5&currency=jpy"
```

#### Using PowerShell
```powershell
# Top cryptocurrencies
Invoke-RestMethod -Uri "http://localhost:7071/api/CryptoDataFunction?action=top&limit=5"

# Bitcoin price
Invoke-RestMethod -Uri "http://localhost:7071/api/CryptoDataFunction?action=coin&coin=bitcoin"
```

#### Using JavaScript (in a web page)
```javascript
// Fetch top cryptocurrencies
fetch('http://localhost:7071/api/CryptoDataFunction?action=top&limit=5')
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      console.log('Top cryptocurrencies:', data.data.results);
    }
  });

// Fetch Bitcoin price
fetch('http://localhost:7071/api/CryptoDataFunction?action=coin&coin=bitcoin')
  .then(response => response.json())
  .then(data => {
    if (data.success) {
      console.log('Bitcoin price:', data.data.current_price);
    }
  });
```

## Supported Cryptocurrencies

This function supports any cryptocurrency available on CoinGecko. Popular coin IDs include:

- `bitcoin` - Bitcoin (BTC)
- `ethereum` - Ethereum (ETH)
- `cardano` - Cardano (ADA)
- `polkadot` - Polkadot (DOT)
- `chainlink` - Chainlink (LINK)
- `litecoin` - Litecoin (LTC)
- `bitcoin-cash` - Bitcoin Cash (BCH)
- `stellar` - Stellar (XLM)

**To find other coin IDs**: Visit https://www.coingecko.com and look at the URL for any coin. For example, Dogecoin's URL is `https://www.coingecko.com/en/coins/dogecoin`, so the coin ID is `dogecoin`.

## Supported Currencies

The function supports these currencies for price conversion:

- `usd` - US Dollar
- `eur` - Euro
- `gbp` - British Pound
- `jpy` - Japanese Yen
- `aud` - Australian Dollar
- `cad` - Canadian Dollar
- `chf` - Swiss Franc
- `cny` - Chinese Yuan
- `sek` - Swedish Krona
- `nzd` - New Zealand Dollar
- `btc` - Bitcoin
- `eth` - Ethereum

## Rate Limiting and Best Practices

### CoinGecko Rate Limits
- **Free tier**: 10-30 requests per minute
- **Rate limit resets**: Every 60 seconds
- **429 errors**: Indicates you've hit the rate limit

### Best Practices
1. **Wait between requests**: Use at least 5-15 seconds between API calls
2. **Cache responses**: Store results for 1-2 minutes to reduce API calls
3. **Handle errors gracefully**: Always check the `success` field in responses
4. **Use appropriate limits**: Don't request more data than you need

### Rate Limit Handling
The function automatically handles rate limits by:
- Retrying failed requests with exponential backoff
- Waiting progressively longer between retry attempts (1s, 3s, 7s)
- Returning appropriate HTTP status codes (429 for rate limits)

## Troubleshooting

### Function Won't Start

**Problem**: `func start` command not found
```
Solution: Install Azure Functions Core Tools
- Download from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local
```

**Problem**: PowerShell version errors
```
Solution: Update PowerShell to version 7.2 or higher
- Download from: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell
```

### API Errors

**Problem**: "Rate limit exceeded" (HTTP 429)
```
Solution: Wait 5-10 minutes before making more requests
- CoinGecko has strict rate limits for free accounts
- Consider upgrading to CoinGecko Pro for higher limits
```

**Problem**: "Coin not found" (HTTP 404)
```
Solution: Check the coin ID spelling
- Visit https://www.coingecko.com to find correct coin IDs
- Use lowercase IDs (e.g., 'bitcoin', not 'Bitcoin')
```

**Problem**: Price shows as 0
```
Solution: This usually indicates:
- Rate limiting from CoinGecko
- Invalid currency parameter
- Temporary API issues
- Try again after a few minutes
```

### Testing Issues

**Problem**: Test script shows "Function endpoint connectivity: Failed"
```
Solution: Make sure the function is running
1. Start the function: func start
2. Verify the URL in the terminal output
3. Use the correct URL in the test script
```

**Problem**: "curl: command not found"
```
Solution for Windows users:
- Use PowerShell: Invoke-RestMethod instead of curl
- Or install curl from: https://curl.se/download.html
```

### Common Issues

**Problem**: JSON parsing errors
```
Solution: Check the response format
- Ensure the function returned valid JSON
- Check for error messages in the function logs
```

**Problem**: Slow response times
```
This is normal for the first request (cold start)
- Subsequent requests should be faster
- CoinGecko API can sometimes be slow
```

## Development and Customization

### Modifying the Function

To customize the function behavior, edit the `run.ps1` file:

1. **Add new parameters**: Modify the parameter extraction section
2. **Change default values**: Update the initialization section
3. **Add new currencies**: Extend the validation list
4. **Modify response format**: Change the data formatting section

### Adding Features

Common enhancements you might want to add:

1. **Caching**: Store API responses to reduce external calls
2. **Additional endpoints**: Support for historical data or market trends
3. **Authentication**: Add API key requirements for production use
4. **Logging**: Enhanced logging for monitoring and debugging

### Deploying to Azure

To deploy this function to Azure:

1. Create an Azure Function App in the Azure portal
2. Configure PowerShell 7.2 as the runtime
3. Deploy using Azure Functions Core Tools:
   ```bash
   func azure functionapp publish <your-function-app-name>
   ```

### Environment Variables

For production deployment, consider setting these environment variables:

- `COINGECKO_API_KEY`: Your CoinGecko Pro API key (if available)
- `CACHE_DURATION`: How long to cache responses (in seconds)
- `MAX_RETRY_ATTEMPTS`: Number of retry attempts for failed API calls

## Support and Resources

### CoinGecko API Documentation
- Official docs: https://www.coingecko.com/en/api/documentation
- Rate limits: https://www.coingecko.com/en/api/pricing
- Coin list: https://api.coingecko.com/api/v3/coins/list

### Azure Functions Documentation
- Getting started: https://docs.microsoft.com/en-us/azure/azure-functions/
- PowerShell reference: https://docs.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell

### Common Error Codes

| HTTP Code | Meaning | Common Cause |
|-----------|---------|--------------|
| 200 | Success | Request completed successfully |
| 400 | Bad Request | Invalid parameters (missing coin, invalid limit, etc.) |
| 404 | Not Found | Coin ID doesn't exist |
| 429 | Rate Limited | Too many requests to CoinGecko |
| 500 | Server Error | Internal function error or CoinGecko issues |
| 503 | Service Unavailable | Network issues or API maintenance |

## License

This project is provided as-is for educational and development purposes. Please respect CoinGecko's terms of service when using their API.

## Contributing

To contribute to this project:

1. Test any changes thoroughly using the provided test script
2. Ensure error handling works correctly
3. Maintain the existing code style and documentation
4. Add comments explaining complex logic

Remember to be respectful of API rate limits during development and testing.