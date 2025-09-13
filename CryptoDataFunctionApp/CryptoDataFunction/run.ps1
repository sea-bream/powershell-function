# ============================================================================
# IMPROVED CRYPTO DATA AZURE FUNCTION - ENHANCED VERSION
# ============================================================================
# Key improvements:
# 1. Better rate limiting handling with exponential backoff
# 2. Fixed single coin market_data extraction
# 3. Enhanced error handling and logging
# 4. Proper API parameter handling
# 5. Caching headers to reduce API calls
# ============================================================================

using namespace System.Net

param($Request, $TriggerMetadata)

Write-Host "=== CRYPTO FUNCTION START ==="

try {
    # ============================================================================
    # STEP 1: EXTRACT AND NORMALIZE PARAMETERS
    # ============================================================================
    Write-Host "Extracting parameters..."

    # Initialize with safe defaults
    $action = "top"
    $coinId = ""
    $currency = "usd"
    $limit = "10"

    # Extract parameters from query string or POST body
    try {
        if ($Request.Query.action) { $action = $Request.Query.action.ToString().Trim().ToLower() }
        if ($Request.Query.coin) { $coinId = $Request.Query.coin.ToString().Trim().ToLower() }
        if ($Request.Query.currency) { $currency = $Request.Query.currency.ToString().Trim().ToLower() }
        if ($Request.Query.limit) { $limit = $Request.Query.limit.ToString().Trim() }

        if ($Request.Body.action) { $action = $Request.Body.action.ToString().Trim().ToLower() }
        if ($Request.Body.coin) { $coinId = $Request.Body.coin.ToString().Trim().ToLower() }
        if ($Request.Body.currency) { $currency = $Request.Body.currency.ToString().Trim().ToLower() }
        if ($Request.Body.limit) { $limit = $Request.Body.limit.ToString().Trim() }
    } catch {
        Write-Host "Parameter extraction warning: $($_.Exception.Message)"
        # Continue with defaults
    }

    Write-Host "Parameters: action='$action', coin='$coinId', currency='$currency', limit='$limit'"

    # ============================================================================
    # STEP 2: ENHANCED VALIDATION
    # ============================================================================
    Write-Host "Validating parameters..."

    # Validate action
    if ($action -ne "coin" -and $action -ne "top") {
        throw "Invalid action '$action'. Supported actions: 'coin', 'top'"
    }

    # Validate coin parameter for coin action
    if ($action -eq "coin" -and ($coinId -eq "" -or $null -eq $coinId)) {
        throw "Coin parameter is required when action is 'coin'"
    }

    # Validate and convert limit
    $limitInt = 10
    try {
        $limitInt = [int]$limit
        if ($limitInt -lt 1 -or $limitInt -gt 250) {
            throw "Limit must be between 1 and 250"
        }
    } catch {
        if ($limit -ne "10") {
            throw "Limit must be a valid number between 1 and 250"
        }
    }

    # Validate currency (basic whitelist)
    $validCurrencies = @("usd", "eur", "gbp", "jpy", "aud", "cad", "chf", "cny", "sek", "nzd", "btc", "eth")
    if ($currency -notin $validCurrencies) {
        Write-Host "Warning: Currency '$currency' may not be supported. Using anyway..."
    }

    Write-Host "Validation passed. limitInt=$limitInt"

    # ============================================================================
    # STEP 3: BUILD OPTIMIZED API URL
    # ============================================================================
    Write-Host "Building API URL..."

    $apiUrl = ""
    $baseUrl = "https://api.coingecko.com/api/v3"

    if ($action -eq "coin") {
        # Single coin endpoint - FIXED: Ensure market_data is included
        $apiUrl = "$baseUrl/coins/$coinId"
        $apiUrl += "?localization=false"
        $apiUrl += "&tickers=false"
        $apiUrl += "&market_data=true"          # Critical: this must be true
        $apiUrl += "&community_data=false"
        $apiUrl += "&developer_data=false"
        $apiUrl += "&sparkline=false"
        Write-Host "Single coin URL: $apiUrl"
    } else {
        # Top coins endpoint with additional price change data
        $apiUrl = "$baseUrl/coins/markets"
        $apiUrl += "?vs_currency=$currency"
        $apiUrl += "&order=market_cap_desc"
        $apiUrl += "&per_page=$limitInt"
        $apiUrl += "&page=1"
        $apiUrl += "&sparkline=false"
        $apiUrl += "&price_change_percentage=1h,24h,7d"
        Write-Host "Top coins URL: $apiUrl"
    }

    # ============================================================================
    # STEP 4: ENHANCED API CALL WITH BETTER RATE LIMITING
    # ============================================================================
    Write-Host "Calling CoinGecko API..."

    # Enhanced headers
    $headers = @{
        'User-Agent' = 'Azure-Function-Crypto-Data/2.0'
        'Accept' = 'application/json'
        'Accept-Encoding' = 'gzip, deflate'
    }

    # Improved retry logic with exponential backoff
    $apiResponse = $null
    $maxAttempts = 3
    $baseDelay = 1000  # Start with 1 second

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Write-Host "API attempt $attempt of $maxAttempts"

            # Progressive delay: 1s, 3s, 7s
            if ($attempt -gt 1) {
                $delay = $baseDelay * ([Math]::Pow(2, $attempt - 1) + 1)
                Write-Host "Waiting $delay ms before retry..."
                Start-Sleep -Milliseconds $delay
            }

            # Make the API call with proper timeout
            $apiResponse = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 20
            Write-Host "API call successful on attempt $attempt"
            break

        } catch {
            $errorMsg = $_.Exception.Message
            $statusCode = "Unknown"

            # Extract status code if available
            if ($_.Exception -match "(\d{3})") {
                $statusCode = $matches[1]
            }

            Write-Host "API attempt $attempt failed: HTTP $statusCode - $errorMsg"

            # Handle different error types
            if ($statusCode -eq "429" -or $errorMsg -match "429|Too Many Requests") {
                if ($attempt -eq $maxAttempts) {
                    throw "Rate limit exceeded after $maxAttempts attempts. Please try again in a few minutes."
                }
                Write-Host "Rate limited, will retry with longer delay..."
            }
            elseif ($statusCode -eq "404" -or $errorMsg -match "404|Not Found") {
                throw "Coin '$coinId' not found. Please check the coin ID."
            }
            elseif ($statusCode -eq "500" -or $errorMsg -match "500|Internal Server Error") {
                if ($attempt -eq $maxAttempts) {
                    throw "CoinGecko API is experiencing issues. Please try again later."
                }
                Write-Host "Server error, will retry..."
            }
            else {
                if ($attempt -eq $maxAttempts) {
                    throw "API error after $maxAttempts attempts: $errorMsg"
                }
                Write-Host "Unknown error, will retry..."
            }
        }
    }

    # ============================================================================
    # STEP 5: ENHANCED DATA PROCESSING AND FORMATTING
    # ============================================================================
    Write-Host "Processing API response..."

    $formattedData = @{}

    if ($action -eq "coin") {
        # ========================================================================
        # IMPROVED SINGLE COIN PROCESSING
        # ========================================================================
        Write-Host "Processing single coin response for: $($apiResponse.name)"

        # Validate response structure
        if (-not $apiResponse.market_data) {
            Write-Host "WARNING: market_data is missing from API response!"
            Write-Host "Available top-level properties: $($apiResponse.PSObject.Properties.Name -join ', ')"

            # Try to get basic info even without market_data
            $formattedData = @{
                id = if ($apiResponse.id) { $apiResponse.id } else { $coinId }
                name = if ($apiResponse.name) { $apiResponse.name } else { "Unknown" }
                symbol = if ($apiResponse.symbol) { $apiResponse.symbol.ToUpper() } else { "" }
                current_price = 0
                market_cap = 0
                market_cap_rank = if ($apiResponse.market_cap_rank) { $apiResponse.market_cap_rank } else { 0 }
                total_volume = 0
                price_change_24h = 0
                price_change_percentage_24h = 0
                circulating_supply = 0
                total_supply = 0
                max_supply = 0
                last_updated = if ($apiResponse.last_updated) { $apiResponse.last_updated } else { "" }
                error_note = "Market data unavailable - this may be due to API changes or rate limiting"
            }
        } else {
            Write-Host "market_data found successfully"

            # Extract comprehensive coin data
            $formattedData = @{
                id = if ($apiResponse.id) { $apiResponse.id } else { $coinId }
                name = if ($apiResponse.name) { $apiResponse.name } else { "Unknown" }
                symbol = if ($apiResponse.symbol) { $apiResponse.symbol.ToUpper() } else { "" }
                current_price = 0
                market_cap = 0
                market_cap_rank = if ($apiResponse.market_cap_rank) { $apiResponse.market_cap_rank } else { 0 }
                total_volume = 0
                price_change_24h = 0
                price_change_percentage_24h = 0
                circulating_supply = 0
                total_supply = 0
                max_supply = 0
                last_updated = if ($apiResponse.last_updated) { $apiResponse.last_updated } else { "" }
            }

            # ENHANCED price extraction with multiple fallback methods
            try {
                $marketData = $apiResponse.market_data

                # Method 1: Direct currency access
                if ($marketData.current_price -and $marketData.current_price.PSObject.Properties[$currency]) {
                    $formattedData.current_price = $marketData.current_price.$currency
                    Write-Host "Price extracted via direct access: $($formattedData.current_price)"
                }
                # Method 2: Hashtable access (for older PowerShell versions)
                elseif ($marketData.current_price -is [hashtable] -and $marketData.current_price.ContainsKey($currency)) {
                    $formattedData.current_price = $marketData.current_price[$currency]
                    Write-Host "Price extracted via hashtable: $($formattedData.current_price)"
                }
                # Method 3: USD fallback
                elseif ($currency -ne "usd" -and $marketData.current_price.PSObject.Properties["usd"]) {
                    $formattedData.current_price = $marketData.current_price.usd
                    Write-Host "Using USD fallback price: $($formattedData.current_price)"
                }

                # Extract other market data using the same pattern
                if ($marketData.market_cap -and $marketData.market_cap.PSObject.Properties[$currency]) {
                    $formattedData.market_cap = $marketData.market_cap.$currency
                }
                if ($marketData.total_volume -and $marketData.total_volume.PSObject.Properties[$currency]) {
                    $formattedData.total_volume = $marketData.total_volume.$currency
                }
                if ($marketData."price_change_24h_in_currency" -and $marketData."price_change_24h_in_currency".PSObject.Properties[$currency]) {
                    $formattedData.price_change_24h = $marketData."price_change_24h_in_currency".$currency
                }
                if ($marketData.price_change_percentage_24h) {
                    $formattedData.price_change_percentage_24h = $marketData.price_change_percentage_24h
                }
                if ($marketData.circulating_supply) {
                    $formattedData.circulating_supply = $marketData.circulating_supply
                }
                if ($marketData.total_supply) {
                    $formattedData.total_supply = $marketData.total_supply
                }
                if ($marketData.max_supply) {
                    $formattedData.max_supply = $marketData.max_supply
                }

            } catch {
                Write-Host "Error extracting market data: $($_.Exception.Message)"
            }
        }

        Write-Host "Single coin formatted: $($formattedData.name) = $($formattedData.current_price) $($currency.ToUpper())"

    } else {
        # ========================================================================
        # ENHANCED TOP COINS PROCESSING
        # ========================================================================
        Write-Host "Processing top coins response: $($apiResponse.Count) coins"

        $formattedData = @{
            currency = $currency.ToUpper()
            total_results = if ($apiResponse.Count) { $apiResponse.Count } else { 0 }
            results = @()
        }

        if ($apiResponse -and $apiResponse.Count -gt 0) {
            foreach ($coin in $apiResponse) {
                $coinData = @{
                    id = if ($coin.id) { $coin.id } else { "" }
                    name = if ($coin.name) { $coin.name } else { "Unknown" }
                    symbol = if ($coin.symbol) { $coin.symbol.ToUpper() } else { "" }
                    current_price = if ($coin.current_price) { $coin.current_price } else { 0 }
                    market_cap = if ($coin.market_cap) { $coin.market_cap } else { 0 }
                    market_cap_rank = if ($coin.market_cap_rank) { $coin.market_cap_rank } else { 0 }
                    total_volume = if ($coin.total_volume) { $coin.total_volume } else { 0 }
                    price_change_24h = if ($coin.price_change_24h) { $coin.price_change_24h } else { 0 }
                    price_change_percentage_24h = if ($coin.price_change_percentage_24h) { $coin.price_change_percentage_24h } else { 0 }
                    price_change_percentage_1h = if ($coin.price_change_percentage_1h_in_currency) { $coin.price_change_percentage_1h_in_currency } else { 0 }
                    price_change_percentage_7d = if ($coin.price_change_percentage_7d_in_currency) { $coin.price_change_percentage_7d_in_currency } else { 0 }
                    circulating_supply = if ($coin.circulating_supply) { $coin.circulating_supply } else { 0 }
                    total_supply = if ($coin.total_supply) { $coin.total_supply } else { 0 }
                    max_supply = if ($coin.max_supply) { $coin.max_supply } else { 0 }
                    last_updated = if ($coin.last_updated) { $coin.last_updated } else { "" }
                }
                $formattedData.results += $coinData
            }
        }

        Write-Host "Top coins formatted successfully: $($formattedData.total_results) coins"
    }

    # ============================================================================
    # STEP 6: BUILD SUCCESS RESPONSE WITH CACHING HEADERS
    # ============================================================================
    $responseBody = @{
        success = $true
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        data = $formattedData
        source = "CoinGecko API v3"
        request_info = @{
            action = $action
            currency = $currency
            coin_id = $coinId
            limit = $limitInt
        }
        api_info = @{
            rate_limit_status = "OK"
            response_cached = $false
        }
    } | ConvertTo-Json -Depth 10

    Write-Host "=== SUCCESS RESPONSE ==="

    # Enhanced response headers with caching
    $responseHeaders = @{
        'Content-Type' = 'application/json'
        'Access-Control-Allow-Origin' = '*'
        'Cache-Control' = 'public, max-age=60'  # Cache for 1 minute
        'X-RateLimit-Remaining' = 'Unknown'
        'X-Function-Version' = '2.0'
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Headers = $responseHeaders
        Body = $responseBody
    })

} catch {
    # ============================================================================
    # ENHANCED ERROR HANDLING
    # ============================================================================
    Write-Host "=== ERROR OCCURRED ==="
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Error type: $($_.Exception.GetType().Name)"
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"

    # Determine appropriate HTTP status code
    $statusCode = [HttpStatusCode]::InternalServerError
    $errorMessage = $_.Exception.Message

    if ($errorMessage -match "Invalid action|Coin parameter is required|Limit must be") {
        $statusCode = [HttpStatusCode]::BadRequest
    }
    elseif ($errorMessage -match "not found|404") {
        $statusCode = [HttpStatusCode]::NotFound
    }
    elseif ($errorMessage -match "Rate limit|429|Too Many Requests") {
        $statusCode = [HttpStatusCode]::TooManyRequests
    }
    elseif ($errorMessage -match "timeout|network|connection") {
        $statusCode = [HttpStatusCode]::ServiceUnavailable
    }

    $errorResponse = @{
        success = $false
        error = $errorMessage
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        request_info = @{
            action = $action
            currency = $currency
            coin_id = $coinId
            limit = $limit
        }
        debug_info = @{
            error_type = $_.Exception.GetType().Name
            line_number = $_.InvocationInfo.ScriptLineNumber
        }
    } | ConvertTo-Json -Depth 5

    Write-Host "=== ERROR RESPONSE ==="

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $statusCode
        Headers = @{
            'Content-Type' = 'application/json'
            'Access-Control-Allow-Origin' = '*'
            'X-Function-Version' = '2.0'
        }
        Body = $errorResponse
    })
}