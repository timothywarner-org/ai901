<#
.SYNOPSIS
    Provisions the Azure infrastructure required for the AI-901 Lesson 04 demo.

.DESCRIPTION
    Deploys, idempotently:
      1. Resource group              rg-ai901-lesson04-demo  (East US 2)
      2. Foundry resource            ai901-lesson04-foundry  (AIServices, S0)
      3. Model deployment            gpt-4o-mini (GlobalStandard, capacity 10)
      4. Log Analytics workspace     log-ai901-lesson04
      5. Application Insights        appi-ai901-lesson04     (workspace-based)
      6. Azure AI Search             srch-ai901-lesson04     (Basic tier)
      7. Storage account             stai901lesson04         + 'data' container + CORS
      8. RBAC grants for the Foundry managed identity on Search and Storage

    Why each piece:
      - Foundry resource gives Speech / Translator / Language as Foundry Tools
        (needed for the Responsible AI portal walkthrough).
      - gpt-4o-mini on GlobalStandard is pay-per-token with no idle charges.
      - App Insights is the destination for Foundry tracing (content-filter audit).
      - Azure AI Search Basic is required by the "Add your data" RAG flow;
        the Free tier does not support semantic ranking.
      - Storage holds the uploaded PDF for "Add your data".
      - CORS on storage is required for the Foundry portal to read uploaded blobs.

    Run again any time -- every step checks for existing resources and skips
    creation when they already match the desired state.

.PARAMETER NameSuffix
    Optional suffix appended to globally-unique resource names if you hit a
    naming collision. Leave empty by default. Example: -NameSuffix "-v2".

.PARAMETER Region
    Primary Azure region. Defaults to East US 2.

.PARAMETER FallbackRegion
    Region to suggest if the model deployment fails due to quota. Defaults to East US.

.EXAMPLE
    .\Deploy-Lesson04-Infrastructure.ps1
    Deploys with all defaults -- the normal path for a practice session.

.EXAMPLE
    .\Deploy-Lesson04-Infrastructure.ps1 -NameSuffix "-v2"
    Re-deploys with new globally-unique names if collisions occur.

.NOTES
    Author:        Tim Warner
    Tested:        PowerShell 7.4+ on Windows 11
    Requirements:  Azure CLI 2.51+, signed in (az login)
    Estimated cost: < $2 per session (Search Basic ~$0.10/hr is the main item).
                    Delete the resource group when done to stop charges.

    Resource names default to "ai901-lessonNN-..." patterns. They must be globally
    unique -- add -NameSuffix if you hit a conflict.

    Changelog:
      1.1  Real $LASTEXITCODE gating via Invoke-Az wrapper.
           Automatic Search region fallback.
           CORS clear switched to --account-key (CLI 2.85.0 compatibility).
           Data-plane RBAC propagation poll before container/CORS calls.
           RBAC create retries 3x for ARM MI-visibility lag.
      1.0  Initial.
#>
#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$NameSuffix = "",

    [Parameter(Mandatory = $false)]
    [string]$Region = "eastus2",

    [Parameter(Mandatory = $false)]
    [string]$FallbackRegion = "eastus"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---------------------------------------------------------------------------
# Helper functions -- consistent console output.
# ---------------------------------------------------------------------------

function Write-Banner {
    param([string]$Title)
    Write-Output ""
    Write-Output "============================================================"
    Write-Output "  $Title"
    Write-Output "============================================================"
    Write-Output ""
}

function Write-Step {
    param([string]$Message)
    Write-Output ""
    Write-Output ">>> $Message"
    Write-Output ""
}

function Write-Success { param([string]$m) Write-Output "[OK]    $m" }
function Write-Info    { param([string]$m) Write-Output "[INFO]  $m" }
function Write-Warn    { param([string]$m) Write-Output "[WARN]  $m" }
function Write-ErrorMsg { param([string]$m) Write-Output "[ERROR] $m" }

# Returns $true if the previous az command succeeded (resource exists).
function Test-AzResource {
    param([string]$ShowCommand)
    $null = Invoke-Expression "$ShowCommand 2>`$null"
    return $LASTEXITCODE -eq 0
}

# Runs an az command and throws if it fails. Use this for every create/grant
# call so a non-zero exit code cannot be followed by a misleading [OK] line.
function Invoke-Az {
    param(
        [Parameter(Mandatory)] [scriptblock]$Action,
        [Parameter(Mandatory)] [string]$FailMessage
    )
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$FailMessage (az exit code $LASTEXITCODE)"
    }
}

# ---------------------------------------------------------------------------
# Variables -- change the defaults here only.
# ---------------------------------------------------------------------------

# NOTE: resource names must be globally unique in Azure. If you hit a conflict,
# re-run with -NameSuffix "-v2" (or any short string).
$ResourceGroup    = "rg-ai901-lesson04-demo$NameSuffix"
$FoundryAccount   = "ai901-lesson04-foundry$NameSuffix"
$FoundryProject   = "ai901-lesson04-project"    # project name is RG-scoped, no global uniqueness needed
$ModelDeployment  = "gpt-4o-mini"
$ModelName        = "gpt-4o-mini"
$ModelVersion     = "2024-07-18"
$ModelSku         = "GlobalStandard"
$ModelCapacity    = 10                           # 10K TPM -- sufficient for a practice session
$LogAnalytics     = "log-ai901-lesson04$NameSuffix"
$AppInsights      = "appi-ai901-lesson04$NameSuffix"
$SearchService    = "srch-ai901-lesson04$NameSuffix"
# Storage account names are lowercase alphanumeric only, max 24 chars.
$StorageAccount   = ("stai901lesson04" + $NameSuffix.Replace("-","").ToLower())
$BlobContainer    = "data"

Write-Banner "AI-901 Lesson 04 Infrastructure Deploy"
Write-Output "  Resource group : $ResourceGroup"
Write-Output "  Region         : $Region (fallback: $FallbackRegion)"
Write-Output "  Foundry        : $FoundryAccount"
Write-Output "  Model          : $ModelName $ModelVersion ($ModelSku, capacity $ModelCapacity)"
Write-Output "  App Insights   : $AppInsights (workspace: $LogAnalytics)"
Write-Output "  AI Search      : $SearchService (Basic)"
Write-Output "  Storage        : $StorageAccount (with container '$BlobContainer')"
Write-Output ""

# ---------------------------------------------------------------------------
# Step 0 -- Verify Azure CLI is installed and you are signed in.
# ---------------------------------------------------------------------------

Write-Step "Step 0: Verifying Azure CLI session"

try {
    $azVersionRaw = az version --output json 2>$null
    $azVersion = ($azVersionRaw | ConvertFrom-Json).'azure-cli'
    Write-Info "Azure CLI version: $azVersion"
} catch {
    Write-ErrorMsg "Azure CLI not found. Install from https://aka.ms/install-azure-cli, then re-run."
    throw
}

try {
    $account = az account show --output json 2>$null | ConvertFrom-Json
} catch {
    Write-ErrorMsg "Not signed in. Run: az login --tenant <your-tenant>"
    throw
}

if (-not $account) {
    Write-ErrorMsg "Not signed in. Run: az login --tenant <your-tenant>"
    throw "az login required"
}

Write-Info "Subscription : $($account.name) ($($account.id))"
Write-Info "Signed in as : $($account.user.name)"

# ---------------------------------------------------------------------------
# Step 1 -- Resource group (idempotent).
# ---------------------------------------------------------------------------

Write-Step "Step 1: Resource group"

if (Test-AzResource "az group show --name $ResourceGroup") {
    Write-Info "Resource group already exists -- skipping create."
} else {
    Invoke-Az -FailMessage "Resource group create failed" -Action {
        az group create --name $ResourceGroup --location $Region --output none
    }
    Write-Success "Created resource group $ResourceGroup in $Region"
}

# ---------------------------------------------------------------------------
# Step 2 -- Foundry resource (kind=AIServices).
#   --custom-domain: required for keyless access via Microsoft Entra ID.
#   --assign-identity: enables the system-assigned managed identity used
#   for keyless inference and for Foundry to reach Search/Storage.
# ---------------------------------------------------------------------------

Write-Step "Step 2: Foundry resource ($FoundryAccount)"

if (Test-AzResource "az cognitiveservices account show --name $FoundryAccount --resource-group $ResourceGroup") {
    Write-Info "Foundry account already exists -- skipping create."
} else {
    Invoke-Az -FailMessage "Foundry account create failed" -Action {
        az cognitiveservices account create `
            --name $FoundryAccount `
            --resource-group $ResourceGroup `
            --location $Region `
            --kind AIServices `
            --sku S0 `
            --custom-domain $FoundryAccount `
            --assign-identity `
            --yes `
            --output none
    }
    Write-Success "Created Foundry account $FoundryAccount"
}

# Pull the managed identity principal ID -- needed for RBAC grants below.
$foundryJson = az cognitiveservices account show `
    --name $FoundryAccount `
    --resource-group $ResourceGroup `
    --output json | ConvertFrom-Json
$foundryMiPrincipal = $foundryJson.identity.principalId
$foundryEndpoint    = $foundryJson.properties.endpoint
Write-Info "Foundry endpoint   : $foundryEndpoint"
Write-Info "MI principal ID    : $foundryMiPrincipal"

# ---------------------------------------------------------------------------
# Step 3 -- Model deployment (gpt-4o-mini on GlobalStandard).
# ---------------------------------------------------------------------------

Write-Step "Step 3: Model deployment ($ModelDeployment)"

if (Test-AzResource "az cognitiveservices account deployment show --name $FoundryAccount --resource-group $ResourceGroup --deployment-name $ModelDeployment") {
    Write-Info "Model deployment already exists -- skipping create."
} else {
    try {
        Invoke-Az -FailMessage "Model deployment create failed" -Action {
            az cognitiveservices account deployment create `
                --name $FoundryAccount `
                --resource-group $ResourceGroup `
                --deployment-name $ModelDeployment `
                --model-name $ModelName `
                --model-version $ModelVersion `
                --model-format OpenAI `
                --sku-capacity $ModelCapacity `
                --sku-name $ModelSku `
                --output none
        }
        Write-Success "Deployed $ModelName $ModelVersion ($ModelSku, capacity $ModelCapacity)"
    } catch {
        Write-ErrorMsg "Model deployment failed. Most likely cause: quota exhausted in $Region."
        Write-Warn  "Retry with: -Region $FallbackRegion (you will need a fresh resource group)."
        throw
    }
}

# ---------------------------------------------------------------------------
# Step 4 -- Log Analytics workspace (required backend for App Insights).
# ---------------------------------------------------------------------------

Write-Step "Step 4: Log Analytics workspace ($LogAnalytics)"

if (Test-AzResource "az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $LogAnalytics") {
    Write-Info "Log Analytics workspace already exists -- skipping create."
} else {
    Invoke-Az -FailMessage "Log Analytics workspace create failed" -Action {
        az monitor log-analytics workspace create `
            --resource-group $ResourceGroup `
            --workspace-name $LogAnalytics `
            --location $Region `
            --output none
    }
    Write-Success "Created Log Analytics workspace $LogAnalytics"
}

$laResourceId = az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $LogAnalytics `
    --query id `
    --output tsv

# ---------------------------------------------------------------------------
# Step 5 -- Application Insights (workspace-based).
#   The Foundry portal's Agents -> Traces tab connects to this resource
#   to store long-term audit logs for content-filter policy review.
# ---------------------------------------------------------------------------

Write-Step "Step 5: Application Insights ($AppInsights)"

# Ensure the app-insights CLI extension is installed (not bundled with core CLI).
$null = az extension show --name application-insights 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Info "Installing 'application-insights' CLI extension..."
    az extension add --name application-insights --output none
}

if (Test-AzResource "az monitor app-insights component show --app $AppInsights --resource-group $ResourceGroup") {
    Write-Info "Application Insights already exists -- skipping create."
} else {
    Invoke-Az -FailMessage "Application Insights create failed" -Action {
        az monitor app-insights component create `
            --app $AppInsights `
            --location $Region `
            --resource-group $ResourceGroup `
            --workspace $laResourceId `
            --kind web `
            --output none
    }
    Write-Success "Created Application Insights $AppInsights"
}

$appInsightsConnectionString = az monitor app-insights component show `
    --app $AppInsights `
    --resource-group $ResourceGroup `
    --query connectionString `
    --output tsv

# ---------------------------------------------------------------------------
# Step 6 -- Azure AI Search (Basic tier).
#   The "Add your data" RAG flow requires Search. Free tier does not support
#   semantic ranking; Basic is the minimum. The script tries the primary
#   region first, then the fallback, and only reports success after the
#   provisioningState confirms the service is up.
# ---------------------------------------------------------------------------

Write-Step "Step 6: Azure AI Search ($SearchService, Basic)"

$searchRegion = $null
if (Test-AzResource "az search service show --name $SearchService --resource-group $ResourceGroup") {
    Write-Info "Search service already exists -- skipping create."
    $searchRegion = az search service show --name $SearchService --resource-group $ResourceGroup --query location --output tsv
} else {
    foreach ($candidate in @($Region, $FallbackRegion)) {
        Write-Info "Attempting Search create in $candidate..."
        $createOutput = az search service create `
            --name $SearchService `
            --resource-group $ResourceGroup `
            --location $candidate `
            --sku Basic `
            --output none 2>&1
        if ($LASTEXITCODE -eq 0) {
            $searchRegion = $candidate
            Write-Success "Created Search service $SearchService (Basic) in $candidate"
            break
        }
        Write-Warn "Search create failed in ${candidate}: $createOutput"
    }
    if (-not $searchRegion) {
        throw "Search create failed in both $Region and $FallbackRegion. Try a different -FallbackRegion (e.g. westus2, southcentralus)."
    }
}

$searchEndpoint = "https://$SearchService.search.windows.net"
Write-Info "Search endpoint    : $searchEndpoint (region: $searchRegion)"

# ---------------------------------------------------------------------------
# Step 7 -- Storage account + 'data' container + CORS for Foundry portal.
# ---------------------------------------------------------------------------

Write-Step "Step 7: Storage account ($StorageAccount)"

if (Test-AzResource "az storage account show --name $StorageAccount --resource-group $ResourceGroup") {
    Write-Info "Storage account already exists -- skipping create."
} else {
    Invoke-Az -FailMessage "Storage account create failed" -Action {
        az storage account create `
            --name $StorageAccount `
            --resource-group $ResourceGroup `
            --location $Region `
            --sku Standard_LRS `
            --kind StorageV2 `
            --access-tier Hot `
            --allow-blob-public-access false `
            --output none
    }
    Write-Success "Created Storage account $StorageAccount"
}

# Container + CORS -- uses Microsoft Entra ID auth so the script works without storage keys.
# RBAC propagation for the current user's Storage Blob Data Contributor role can lag
# account creation by 30-60s on a fresh deploy. Poll briefly before issuing the calls.
Write-Info "Waiting for data-plane RBAC propagation (max 90s)..."
$ready = $false
for ($i = 0; $i -lt 9; $i++) {
    $null = az storage container exists `
        --name $BlobContainer `
        --account-name $StorageAccount `
        --auth-mode login `
        --output none 2>$null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 10
}
if (-not $ready) {
    Write-Warn "Data-plane RBAC still propagating -- container/CORS calls may fail. If so, re-run the script in 1-2 minutes."
}

$null = az storage container show `
    --name $BlobContainer `
    --account-name $StorageAccount `
    --auth-mode login `
    --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    Invoke-Az -FailMessage "Blob container create failed" -Action {
        az storage container create `
            --name $BlobContainer `
            --account-name $StorageAccount `
            --auth-mode login `
            --output none
    }
    Write-Success "Created blob container '$BlobContainer'"
} else {
    Write-Info "Container '$BlobContainer' already exists -- skipping create."
}

# CORS -- required for the Foundry portal to read blobs during "Add your data".
# NB: 'az storage cors clear' does not accept --auth-mode on CLI 2.85.0.
# Pull a storage key just for this one call; the key is not stored or logged.
$storageKey = az storage account keys list `
    --account-name $StorageAccount `
    --resource-group $ResourceGroup `
    --query "[0].value" --output tsv
$null = az storage cors clear `
    --services b `
    --account-name $StorageAccount `
    --account-key $storageKey `
    --output none 2>$null
Invoke-Az -FailMessage "CORS add failed" -Action {
    az storage cors add `
        --services b `
        --methods DELETE GET HEAD MERGE OPTIONS POST PUT `
        --origins "https://ai.azure.com" "https://oai.azure.com" "https://documentintelligence.ai.azure.com" `
        --allowed-headers "*" `
        --exposed-headers "*" `
        --max-age 3600 `
        --account-name $StorageAccount `
        --auth-mode login `
        --output none
}
Write-Success "CORS configured for Foundry portal origins"

# ---------------------------------------------------------------------------
# Step 8 -- RBAC grants for the Foundry managed identity.
#   "Add your data" needs the Foundry MI to read from Storage and query Search.
#   Role IDs are stable across tenants:
#     Storage Blob Data Reader:   2a2b9908-6ea1-4ae2-8e65-a410df84e7d1
#     Search Index Data Reader:   1407120a-92aa-4202-b7e9-c0e197c71c8f
#     Search Service Contributor: 7ca78c08-252a-4471-8644-bb5ff32d4ba0
# ---------------------------------------------------------------------------

Write-Step "Step 8: RBAC grants for Foundry managed identity"

$storageScope = az storage account show `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --query id --output tsv
if ([string]::IsNullOrWhiteSpace($storageScope)) {
    throw "Could not resolve storage account scope -- Step 7 did not complete."
}

$searchScope = az search service show `
    --name $SearchService `
    --resource-group $ResourceGroup `
    --query id --output tsv
if ([string]::IsNullOrWhiteSpace($searchScope)) {
    throw "Could not resolve search service scope -- Step 6 did not complete."
}

$rbacAssignments = @(
    @{ Role = "Storage Blob Data Reader"; Scope = $storageScope },
    @{ Role = "Search Index Data Reader"; Scope = $searchScope },
    @{ Role = "Search Service Contributor"; Scope = $searchScope }
)

foreach ($assignment in $rbacAssignments) {
    $existing = az role assignment list `
        --assignee $foundryMiPrincipal `
        --role $assignment.Role `
        --scope $assignment.Scope `
        --output json 2>$null | ConvertFrom-Json
    if ($existing -and $existing.Count -gt 0) {
        Write-Info "Role '$($assignment.Role)' already assigned -- skipping."
        continue
    }

    # ARM eventual consistency: a brand-new MI principal can take 10-20s
    # to be visible to RBAC. Retry up to 3 times.
    $attempt = 0
    $granted = $false
    while (-not $granted -and $attempt -lt 3) {
        $attempt++
        $null = az role assignment create `
            --assignee-object-id $foundryMiPrincipal `
            --assignee-principal-type ServicePrincipal `
            --role $assignment.Role `
            --scope $assignment.Scope `
            --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $granted = $true
        } else {
            Write-Warn "RBAC attempt $attempt for '$($assignment.Role)' failed -- retrying in 15s..."
            Start-Sleep -Seconds 15
        }
    }
    if (-not $granted) {
        throw "RBAC grant '$($assignment.Role)' on $($assignment.Scope) failed after 3 attempts."
    }
    Write-Success "Granted '$($assignment.Role)' to Foundry MI"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

Write-Banner "Deploy Summary"
Write-Output "Subscription              : $($account.name)"
Write-Output "Resource group            : $ResourceGroup"
Write-Output "Region                    : $Region"
Write-Output ""
Write-Output "Foundry endpoint          : $foundryEndpoint"
Write-Output "Model deployment          : $ModelDeployment ($ModelName $ModelVersion)"
Write-Output "App Insights connection   : $appInsightsConnectionString"
Write-Output "Search endpoint           : $searchEndpoint (region: $searchRegion)"
Write-Output "Storage account           : $StorageAccount (container: $BlobContainer)"
Write-Output ""
Write-Output "Foundry portal URL        : https://ai.azure.com/build/overview"
Write-Output ""

# ---------------------------------------------------------------------------
# Manual follow-up -- two steps Azure CLI cannot do reliably today.
# ---------------------------------------------------------------------------

Write-Banner "TWO MANUAL STEPS (do these in the Foundry portal)"
Write-Output ""
Write-Output "1. Create the Foundry project '$FoundryProject':"
Write-Output "     a. Open https://ai.azure.com"
Write-Output "     b. Click + Create project (top-right)"
Write-Output "     c. Project name: $FoundryProject"
Write-Output "     d. Foundry resource: $FoundryAccount  (already exists, pick from dropdown)"
Write-Output "     e. Click Create. Takes ~1 minute."
Write-Output ""
Write-Output "2. Connect Application Insights to the project for tracing:"
Write-Output "     a. In the project, left nav -> Agents -> Traces tab"
Write-Output "     b. Click Connect"
Write-Output "     c. Pick: $AppInsights  (already exists, in $ResourceGroup)"
Write-Output "     d. Click Connect again to confirm."
Write-Output ""
Write-Output "Why these two are manual: the Azure CLI 'project create' and 'connect"
Write-Output "tracing' verbs for the new Microsoft Foundry are still in flux as of"
Write-Output "mid-2026. They are one-click in the portal and take under two minutes."
Write-Output ""

Write-Banner "CLEANUP (run when you are done)"
Write-Output ""
Write-Output "  az group delete --name $ResourceGroup --yes --no-wait"
Write-Output ""
Write-Output "One async command, ~10 minutes to fully delete. No charges after delete completes."
Write-Output 'Estimated cost for the session: under $2 (Search Basic at ~$0.10/hr is the main item).'
Write-Output ""

Write-Success "Lesson 04 infrastructure deploy complete."
