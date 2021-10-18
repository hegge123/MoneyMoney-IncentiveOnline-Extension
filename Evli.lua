WebBanking{version = 1.00,
    url = "https://incentive.online/",
    services = {"Evli savings","Evli portfolio" },
    description = "Fetches Data Incentiv Online Platform from EVLI Bank - Evli Awards Management Oy"
}

local connection = nil
local loginresponse = nil
local connection = Connection()
local URL_Portfolio = 'https://incentive.online/web/eam-holder/evli-portfolio'
local URL_HolderInfo = 'https://incentive.online/web/eam-holder/my-info'
local URLshare_purchases = 'https://incentive.online/web/eam-holder/share-purchases'
local URLsavings = 'https://incentive.online/web/eam-holder/savings'
local URL_transactions = 'https://incentive.online/web/eam-holder/evli-transactions'
local URL_start = 'https://incentive.online/web/eam-holder'

function SupportsBank (protocol, bankCode)
    return protocol == ProtocolWebBanking and bankCode == "Evli portfolio"
end

function InitializeSession (protocol, bankCode, username, customer, password)
    connection.language = "en-EN"
    local response = HTML(connection:get(url))

    response:xpath("//input[@name='_58_login']"):attr("value", username)
    response:xpath("//input[@name='_58_password']"):attr("value", password)
    loginresponse = HTML(connection:request(response:xpath("//*[@id='login']"):click()))

    -- Wrong Error Text used correct me
    if (loginresponse:xpath("//*[@class='alert alert-error']"):text() == "Keine gültigen Zugangsdaten.") then
        return LoginFailed
    end
end

function ListAccounts (knownAccounts)

    local response = HTML(connection:get(URL_HolderInfo))
    local portfolioID = response:xpath("/html/body/div[1]/div[2]/div/span/div/div/div/div/div/div[2]/section[1]/section/div/div/div/span"):text()
    local accountID = response:xpath("/html/body/div[1]/div[2]/div/span/div/div/div/div/div/div[2]/section[3]/section/div[3]/div/div[2]/div/div/span[1]"):text()
    local accounts = {}
    -- Return array of accounts.
    table.insert (
        accounts, 
        {
            name = "Evli Savings",
            accountNumber = accountID,
            currency = "SEK",
            portfolio = false,
            type = "AccountTypeSavings"
        }
        )
    table.insert (
        accounts,
        {
            name = "Evli Portfolio",
            accountNumber = portfolioID,
            currency = "SEK",
            portfolio = true,
            type = "AccountTypePortfolio"
        }
        )
        --[[
            table.insert (
                accounts,
                {
                    name = "Evli Awards",
                    accountNumber = "Awards",
                    currency = "SEK",
                    portfolio = true,
            type = "AccountTypePortfolio"
        })
        ]]--
    return accounts
end

function RefreshAccount (account, since)
    if account.portfolio then
        -- Refresh Portfolio
        local instruments = {}
        local portfolioPageHTML = HTML(connection:get(URL_Portfolio))
        local startPageHTMLPriceandHistoryDashboard = HTML(connection:get(URL_start)):xpath("//div[@class='share-description']"):children()
        local price = toLocalNum(startPageHTMLPriceandHistoryDashboard:get(3):xpath("//h3/span[@class='price']"):text())
        local market = startPageHTMLPriceandHistoryDashboard:get(2):children():get(2):text()

        local tradeTimestamp = toPOSIXDate(startPageHTMLPriceandHistoryDashboard:get(2):children():get(3):text())
        local instrumentTable = portfolioPageHTML:xpath("//div[@id='id4____evliCustodyBalances__WAR__holderui__']/div/table[@class='materials-table transaction-table-holder evli-positions-table']/tbody"):children()
        
        for i = 1 , instrumentTable:length()-2 do
            local rowData = instrumentTable:get(i):children()
            local instrumentMetaData = rowData:get(1):children():get(1):children()

            local name = instrumentMetaData:get(1):text()
            local isin = instrumentMetaData:get(2):text()
            local quantity = toLocalNum(rowData:get(3):text()) --Nominalbetrag oder Stückzahl
            local amount = toLocalNum(rowData:get(5):children():get(1):text()) --Wert der Depotposition in Kontowährung
            local purchaseValue = toLocalNum(rowData:get(4):children():get(1):text()) -- Aktueller Preis oder Kurs
            local purchasePrice = purchaseValue / quantity
            table.insert(
                instruments, 
                {
                    name = name,
                    isin = isin,
                    market = market,
                    tradeTimestamp = tradeTimestamp,
                    currency = "SEK",
                    quantity = quantity,
                    purchasePrice = purchasePrice,
                    amount = amount ,
                    price = price, 
                    currencyOfPrice = "SEK", 
                    currencyOfPurchasePrice = "SEK"
                })

        end
        return {securities=instruments}
    else
        -- Refresh Savings account
        local eventName = ""
        -- payments to the bank
        local savingsPageHTML = HTML(connection:get(URLsavings))
        local balance = savingsPageHTML:xpath("//tfoot/tr[@class='event-summary-row']"):children():get(6):text()
        balance = toLocalNum(balance)
        -- Saveings:
        eventName = savingsPageHTML:xpath("//tbody[@id='tablebody']/div/div/tr/td/a"):text()
        local savingsTableRows = savingsPageHTML:xpath("//table[@class='event-details-table']/tbody/tr[@class='event-table-row']")
        local savings = {}
        local len = savingsTableRows:length()

        for i=1,len do
            local row = nil
            row = savingsTableRows:get(i):children()
            if row:get(1):text() == "Savings" then

                local amount = 0.00
                local purpose = ""
                local bookingDate = nil
                local localCurrency = "" -- for the LC field in Table

                purpose = row:get(1):text()
                localCurrency = row:get(4):text()
                purpose = purpose .."\n"..eventName .." LC:" ..localCurrency .."€"

                amount = toLocalNum( row:get(3):text() )
                bookingDate = toPOSIXDate( row:children():get(1):text() )
                
                table.insert (
                    savings, {
                        bookingDate = bookingDate,
                        purpose = purpose,
                        amount = amount
                    })
            end
        end
        -- Sharepurchases
        local transactionHistory = HTML(connection:get(URLshare_purchases)):xpath("//tbody[@id='tablebody']/div/div/tr/td/div/div/table/tbody"):children()

        for i=3,transactionHistory:length()-1 do -- igonre first 2 rows and last row
            local td = transactionHistory:get(i):children()
            local amount = 0.00
            local purpose = ""
            local bookingDate = nil
            local localCurrency = ""

            purpose = td:get(1):text() .."\n" .."Shars:" ..td:get(3):text()  ..", Price per Share: " ..td:get(4):text()  .."SEK, LC: " ..td:get(6):text() .."€"
            bookingDate = toPOSIXDate(td:get(2):children():get(1):text())
            amount = toLocalNum(td:get(5):text())

            table.insert (
                savings, {
                    bookingDate = bookingDate,
                    purpose = purpose,
                    amount = amount
                })
            -- End For Purchases
        end
        return {balance=balance, transactions=savings}
        -- End IF
    end
end

function EndSession ()

end

function toLocalNum( currencyString )
    currencyString = currencyString:gsub(",","."):gsub( "%s+","" ):gsub("SEK" , "")
    currencyNumber = tonumber(currencyString)
    if not currencyNumber then
        currencyNumber = 0.00
    end
    return currencyNumber
end

function toPOSIXDate( dateString )
    local date = {}
    for match in (dateString.."."):gmatch("(.-)%.") do
        table.insert(date, match);
    end
    return os.time{year = date[3], month = date[2] , day = date[1]}
end