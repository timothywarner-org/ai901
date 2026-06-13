<#
.SYNOPSIS
    Provisions (or tears down) the Azure infrastructure for the AI-901 Lesson 11 demo --
    Create and Test a Single-Agent Solution in the Foundry Portal (Agent Service +
    Python SDK bookend).

.DESCRIPTION
    Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video).
    Lesson 11 is the first half of Domain 2's agent coverage. The lesson is portal-first:
    three beats build a single-agent solution (instructions + File Search knowledge +
    Code Interpreter + trace panel), then a ~30-line Python SDK bookend calls the same
    agent via the AgentsClient surface (threads + messages + runs).

    NEW FOUNDRY, NOT CLASSIC HUB. A Foundry AIServices resource owns the project; no
    separate Azure AI Hub. New Foundry is what the Agent Service runs on.

    Resources provisioned in the resource group (East US 2 default):

      * <FoundryName>         -- Foundry AIServices resource (S0, kind=AIServices)
                                 with project management enabled.
      * <ProjectName>         -- Foundry project (child of the resource). Owns the
                                 gpt-4o deployment AND the agent you build in Beats 1-3.
      * gpt-4o deployment     -- the tool-capable chat model the agent uses.
                                 gpt-4o 2024-11-20 is the function-calling-capable
                                 flagship -- non-function-calling models silently
                                 ignore tools, which is the single most common
                                 Lesson 11 troubleshooting trap.
      * Log Analytics workspace + Application Insights -- observability for tracing.

    What this script does NOT do:
      * Create the agent. The first step of the lesson builds the agent in the Foundry
        portal by hand -- that build sequence IS the LO 2.4.1 demo. Provisioning the
        agent here would defeat the lesson.
      * Upload knowledge files. A later step uploads them by drag-drop from the
        demo/agent-files/ folder -- a live demonstration of File Search attach.

    Why gpt-4o (not gpt-4o-mini):
      The Agent Service requires a tool-capable model for function calling. gpt-4o
      2024-11-20 is on the function-calling supported-models list and is the
      correct choice for this lesson's agent and File Search capabilities.

    Cost: < $0.50 per learning session. Run -Cleanup promptly after you finish.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson11-demo.
    Change this if the name conflicts with an existing resource group in your subscription.

.PARAMETER Location
    Primary Azure region. Default: swedencentral.
    Supported values: swedencentral, japaneast, southindia, norwayeast,
    polandcentral, westus3, eastus2. Pick the region closest to you that
    has confirmed gpt-4o quota.

.PARAMETER FoundryName
    Azure resource name for the Foundry (AIServices) account.
    Default: ai901-lesson11-foundry. MUST be globally unique -- change the
    suffix if you see a name-conflict error (e.g. ai901-lesson11-foundry-abc).

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson11-project.

.PARAMETER ChatDeploymentName
    Name of the chat (agent base) deployment. Default: gpt-4o.

.PARAMETER LogAnalyticsName
    Log Analytics workspace name for tracing. Default: law-ai901-lesson11.

.PARAMETER AppInsightsName
    Application Insights resource name. Default: appi-ai901-lesson11.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.PARAMETER WhatIf
    Dry-run. Prints what would happen without making Azure changes.

.EXAMPLE
    .\Deploy-Lesson11-Infrastructure.ps1
    Idempotent deploy with default names. Safe to rerun.

.EXAMPLE
    .\Deploy-Lesson11-Infrastructure.ps1 -FoundryName ai901-lesson11-xyz
    Use a custom globally-unique name to avoid name conflicts.

.EXAMPLE
    .\Deploy-Lesson11-Infrastructure.ps1 -Cleanup
    Async delete the resource group and every resource inside it.

.NOTES
    Prerequisites:
      * Azure CLI (https://aka.ms/azurecli) -- run `az login` before this script.
      * Contributor + User Access Administrator on the target subscription, OR
        Owner (needed to assign the Cognitive Services OpenAI User RBAC role).
    GUI fallback: Every step is also reproducible via the Foundry portal at
    https://ai.azure.com -- see the lesson demo notes.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson11-demo',

    [Parameter()]
    [ValidateSet('swedencentral', 'japaneast', 'southindia', 'norwayeast',
                 'polandcentral', 'westus3', 'eastus2')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    # Must be globally unique. Change the suffix if you get a name-conflict error.
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson11-foundry',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson11-project',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4o',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{4,63}$')]
    [string]$LogAnalyticsName = 'law-ai901-lesson11',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,255}$')]
    [string]$AppInsightsName = 'appi-ai901-lesson11',

    [Parameter()]
    [switch]$Cleanup
)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

function Write-Section {
    param([string]$Title)
    $bar = ('=' * 78)
    Write-Host ''
    Write-Host $bar -ForegroundColor Cyan
    Write-Host (' ' + $Title) -ForegroundColor Cyan
    Write-Host $bar -ForegroundColor Cyan
}

function Write-Status {
    param(
        [ValidateSet('OK', 'SKIP', 'WAIT', 'FAIL')][string]$Kind,
        [string]$Message
    )
    # Glyphs carry the meaning (not color alone) -- accessible for colorblind reading.
    $glyph, $color = switch ($Kind) {
        'OK'   { '[ OK ]', 'Green'   }
        'SKIP' { '[SKIP]', 'Yellow'  }
        'WAIT' { '[WAIT]', 'Cyan'    }
        'FAIL' { '[FAIL]', 'Red'     }
    }
    Write-Host "$glyph $Message" -ForegroundColor $color
}

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Args)
    $raw = & az @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Args -join ' ') failed: $raw"
    }
    return $raw
}

# ----------------------------------------------------------------------------
# Prerequisite checks
# ----------------------------------------------------------------------------

Write-Section 'Prerequisite checks'

$azVersion = & az version --output tsv 2>$null | Select-Object -First 1
if (-not $azVersion) {
    Write-Status FAIL 'Azure CLI not found. Install: https://aka.ms/azurecli'
    exit 1
}
Write-Status OK "Azure CLI present ($azVersion)"

try {
    $accountJson = & az account show --output json 2>$null
    if (-not $accountJson) { throw 'no session' }
    $acct = $accountJson | ConvertFrom-Json
} catch {
    Write-Status FAIL "Not signed in. Run: az login"
    exit 1
}
Write-Status OK "Signed in as $($acct.user.name) -- subscription: $($acct.name)"

$rpState = ((Invoke-Az -Args @('provider','show','--namespace','Microsoft.CognitiveServices','--query','registrationState','-o','tsv')) -join '').Trim()
if ($rpState -ne 'Registered') {
    Write-Status WAIT 'Registering Microsoft.CognitiveServices provider...'
    Invoke-Az -Args @('provider','register','--namespace','Microsoft.CognitiveServices') | Out-Null
}
Write-Status OK 'Microsoft.CognitiveServices provider registered'

# ----------------------------------------------------------------------------
# Cleanup branch
# ----------------------------------------------------------------------------

if ($Cleanup) {
    Write-Section "Cleanup: deleting resource group $ResourceGroup"
    $exists = ((Invoke-Az -Args @('group','exists','--name',$ResourceGroup,'-o','tsv')) -join '').Trim()
    if ($exists -eq 'true') {
        if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Delete resource group')) {
            Invoke-Az -Args @('group','delete','--name',$ResourceGroup,'--yes','--no-wait') | Out-Null
            Write-Status OK 'Delete submitted (async). Resources will be gone in ~5-10 min.'
        }
    } else {
        Write-Status SKIP "Resource group $ResourceGroup does not exist -- nothing to delete."
    }
    return
}

# ----------------------------------------------------------------------------
# Resource group (idempotent)
# ----------------------------------------------------------------------------

Write-Section "Resource group: $ResourceGroup in $Location"

$exists = ((Invoke-Az -Args @('group','exists','--name',$ResourceGroup,'-o','tsv')) -join '').Trim()
if ($exists -eq 'true') {
    Write-Status SKIP 'Resource group already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Create resource group')) {
        Invoke-Az -Args @(
            'group','create',
            '--name', $ResourceGroup,
            '--location', $Location,
            '--tags', 'purpose=ai901-lesson11-demo', 'owner=ai901-student', 'cleanup=true',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry AIServices resource (new Foundry -- the resource that owns the project
# AND the Agent Service)
# ----------------------------------------------------------------------------

Write-Section "Foundry AIServices resource: $FoundryName"

$existingAcct = & az cognitiveservices account show `
    --name $FoundryName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP 'Foundry resource already exists.'
} else {
    # Idempotency across deploy -> cleanup -> deploy: a same-named account deleted
    # recently sits in a SOFT-DELETED state and blocks recreation. The custom-subdomain
    # reservation is GLOBAL, and the ghost may live in a DIFFERENT region/RG than this
    # deploy, so we purge it in ITS original location, parsed from the deleted-account
    # record -- NOT $Location.
    $ghost = & az cognitiveservices account list-deleted -o json 2>$null |
        ConvertFrom-Json | Where-Object { $_.name -eq $FoundryName } | Select-Object -First 1
    if ($ghost) {
        $ghostLoc = if ($ghost.location) { $ghost.location } else { ($ghost.id -split '/locations/')[1].Split('/')[0] }
        $ghostRg  = ($ghost.id -split '/resourceGroups/')[1].Split('/')[0]
        Write-Status WAIT "Purging soft-deleted $FoundryName in $ghostLoc (global subdomain reservation)..."
        & az cognitiveservices account purge --location $ghostLoc --resource-group $ghostRg --name $FoundryName --output none 2>$null
        Start-Sleep -Seconds 5   # let the purge settle before recreating
    }
    if ($PSCmdlet.ShouldProcess($FoundryName, 'Create Foundry AIServices resource')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--name', $FoundryName,
            '--resource-group', $ResourceGroup,
            '--kind', 'AIServices',
            '--sku', 'S0',
            '--location', $Location,
            '--custom-domain', $FoundryName,
            '--assign-identity',
            '--yes',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Foundry resource created.'
    }
}

$projMgmt = (Invoke-Az -Args @(
    'cognitiveservices','account','show',
    '--name',$FoundryName,'--resource-group',$ResourceGroup,
    '--query','properties.allowProjectManagement','-o','tsv'
)) -join ''
if ($projMgmt -ne 'True') {
    if ($PSCmdlet.ShouldProcess($FoundryName, 'Enable project management')) {
        Invoke-Az -Args @(
            'resource','update',
            '--resource-group',$ResourceGroup,
            '--name',$FoundryName,
            '--resource-type','Microsoft.CognitiveServices/accounts',
            '--set','properties.allowProjectManagement=true',
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Project management enabled (this is what makes it a Foundry resource).'
    }
} else {
    Write-Status SKIP 'Project management already enabled.'
}

# ----------------------------------------------------------------------------
# Foundry project (child of the resource -- new Foundry shape)
# ----------------------------------------------------------------------------

Write-Section "Foundry project: $ProjectName"

$existingProj = & az cognitiveservices account project show `
    --name $FoundryName --resource-group $ResourceGroup `
    --project-name $ProjectName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingProj) {
    Write-Status SKIP 'Foundry project already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ProjectName, 'Create Foundry project')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','project','create',
            '--resource-group',$ResourceGroup,
            '--name',$FoundryName,
            '--project-name',$ProjectName,
            '--location',$Location,
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Foundry project created.'
    }
}

# ----------------------------------------------------------------------------
# Model deployment: gpt-4o (the tool-capable base model for the agent)
# ----------------------------------------------------------------------------
# gpt-4o 2024-11-20 is GenerallyAvailable AND on the function-calling supported-
# models list. Non-tool-capable models silently ignore attached tools, which is
# the single most common Lesson 11 troubleshooting trap. We deploy as
# GlobalStandard (450k TPM headroom) to dodge regional capacity walls.

$ChatModelName = 'gpt-4o'
$ChatModelVersion = '2024-11-20'   # GA, function-calling supported

Write-Section "Model deployment: $ChatDeploymentName -> $ChatModelName ($ChatModelVersion)"

$existingChat = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ChatDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingChat) {
    Write-Status SKIP 'Chat deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ChatDeploymentName, "Create $ChatModelName chat deployment")) {
        Write-Status WAIT "Creating $ChatDeploymentName -> $ChatModelName (this can take 30-90s)..."
        $deployOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $ChatDeploymentName `
            --model-name $ChatModelName `
            --model-version $ChatModelVersion `
            --model-format 'OpenAI' `
            --sku-capacity 10 `
            --sku-name 'GlobalStandard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Chat deployment failed: $deployOutput"
            Write-Host ''
            Write-Host "Most likely cause: $ChatModelName GlobalStandard capacity/quota in $Location." -ForegroundColor Yellow
            Write-Host '  Quick fix: re-run with -Location japaneast or southindia (both have confirmed quota),' -ForegroundColor Yellow
            Write-Host '  or request more at https://aka.ms/oai/quotaincrease.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Chat deployment created.'
    }
}

# ----------------------------------------------------------------------------
# RBAC: assign Cognitive Services OpenAI User to the signed-in user
# ----------------------------------------------------------------------------
# The agent SDK call uses DefaultAzureCredential -- it picks up your az-login
# token. That token needs the Cognitive Services OpenAI User role on the Foundry
# resource for chat calls to succeed. Owner-on-the-subscription does NOT
# implicitly grant it (the data-plane RBAC trap -- exam-favorite gotcha).

Write-Section 'RBAC: Cognitive Services OpenAI User on the Foundry resource'

$signedInOid = (Invoke-Az -Args @('ad','signed-in-user','show','--query','id','-o','tsv')) -join ''
$scope = "/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryName"
$existingRole = (Invoke-Az -Args @('role','assignment','list',
    '--assignee', $signedInOid, '--scope', $scope,
    '--role', 'Cognitive Services OpenAI User',
    '--query', '[].id', '-o', 'tsv')) -join ''
if ([string]::IsNullOrWhiteSpace($existingRole)) {
    if ($PSCmdlet.ShouldProcess($scope, 'Assign Cognitive Services OpenAI User')) {
        Invoke-Az -Args @(
            'role','assignment','create',
            '--assignee', $signedInOid,
            '--role', 'Cognitive Services OpenAI User',
            '--scope', $scope,
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Cognitive Services OpenAI User role assigned to signed-in user.'
        Write-Status WAIT 'Role assignment can take up to 5 minutes to propagate (exam-favorite gotcha).'
    }
} else {
    Write-Status SKIP 'Role assignment already in place.'
}

# ----------------------------------------------------------------------------
# Observability: workspace-based Application Insights for Foundry tracing
# ----------------------------------------------------------------------------
# New Foundry does NOT auto-provision Application Insights -- you create (or
# connect) a resource once, then click Connect in the project's Agents -> Traces
# tab. Classic Application Insights is retired, so we use a workspace-based
# resource: a Log Analytics workspace first, then the App Insights component
# bound to it.

Write-Section "Observability: Log Analytics + Application Insights ($AppInsightsName)"

& az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors 2>$null | Out-Null

# Log Analytics workspace (idempotent)
$existingLaw = & az monitor log-analytics workspace show `
    --resource-group $ResourceGroup --workspace-name $LogAnalyticsName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingLaw) {
    Write-Status SKIP 'Log Analytics workspace already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($LogAnalyticsName, 'Create Log Analytics workspace')) {
        Write-Status WAIT "Creating Log Analytics workspace $LogAnalyticsName..."
        Invoke-Az -Args @(
            'monitor','log-analytics','workspace','create',
            '--resource-group', $ResourceGroup,
            '--workspace-name', $LogAnalyticsName,
            '--location', $Location,
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Log Analytics workspace created.'
    }
}
$lawId = (Invoke-Az -Args @('monitor','log-analytics','workspace','show',
    '--resource-group', $ResourceGroup, '--workspace-name', $LogAnalyticsName,
    '--query','id','-o','tsv')) -join ''

# Application Insights component bound to the workspace (idempotent)
$existingAi = & az monitor app-insights component show `
    --resource-group $ResourceGroup --app $AppInsightsName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAi) {
    Write-Status SKIP 'Application Insights resource already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($AppInsightsName, 'Create Application Insights resource')) {
        Write-Status WAIT "Creating Application Insights $AppInsightsName (workspace-based)..."
        Invoke-Az -Args @(
            'monitor','app-insights','component','create',
            '--resource-group', $ResourceGroup,
            '--app', $AppInsightsName,
            '--location', $Location,
            '--workspace', $lawId,
            '--application-type', 'web',
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Application Insights resource created.'
        Write-Status WAIT 'Connect it to the project in Foundry: Agents -> Traces -> Connect (one click).'
    }
}

# ----------------------------------------------------------------------------
# Collect outputs
# ----------------------------------------------------------------------------

Write-Section 'Collecting deployment metadata'

$foundryEp      = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$identityOid    = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','identity.principalId','-o','tsv')) -join ''
$projectEndpoint = ($foundryEp.TrimEnd('/') -replace 'cognitiveservices\.azure\.com','services.ai.azure.com') + "/api/projects/$ProjectName"

# ----------------------------------------------------------------------------
# Smoke test: plain chat call against the gpt-4o deployment
# ----------------------------------------------------------------------------

Write-Section 'Smoke test: chat completion against gpt-4o deployment'

$foundryKey = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$FoundryName,'--query','key1','-o','tsv')) -join ''
$body = @{
    messages = @(
        @{ role = 'system'; content = 'You return one word.' },
        @{ role = 'user';   content = 'Say OK.' }
    )
    max_tokens = 10
} | ConvertTo-Json -Depth 10 -Compress
$uri = "${foundryEp}openai/deployments/$ChatDeploymentName/chat/completions?api-version=2024-10-21"
try {
    $smokeObj = Invoke-RestMethod -Method POST -Uri $uri `
        -Headers @{ 'api-key' = $foundryKey; 'Content-Type' = 'application/json' } `
        -Body $body -ErrorAction Stop
    if ($smokeObj.choices) {
        $content = $smokeObj.choices[0].message.content
        Write-Status OK "Smoke test passed (HTTP 200; model id: $($smokeObj.model); content: $content)."
    } else {
        Write-Status FAIL "Smoke test response unexpected: $($smokeObj | ConvertTo-Json -Compress)"
    }
} catch {
    Write-Status FAIL "Smoke test threw: $($_.Exception.Message)"
}

# ----------------------------------------------------------------------------
# Final summary
# ----------------------------------------------------------------------------

Write-Section 'Deployment complete'

$result = [pscustomobject]@{
    SubscriptionName    = $acct.name
    SubscriptionId      = '<your-subscription-id>'
    ResourceGroup       = $ResourceGroup
    Region              = $Location
    FoundryResource     = $FoundryName
    FoundryProject      = $ProjectName
    ProjectEndpoint     = $projectEndpoint
    ChatDeployment      = $ChatDeploymentName
    ChatModel           = "$ChatModelName ($ChatModelVersion, GlobalStandard, cap 10) -- tool-capable"
    ManagedIdentityOid  = $identityOid
    LogAnalytics        = $LogAnalyticsName
    AppInsights         = "$AppInsightsName (workspace-based; connect in Foundry Traces tab)"
    PortalUrl           = "https://portal.azure.com/#resource/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/overview"
    FoundryPortalUrl    = 'https://ai.azure.com/'
    AgentId             = '(build in the Foundry portal -> Agents tab; copy the ID into .env)'
}

$result | Format-List

Write-Host ''
Write-Host 'Paste into demo\.env BEFORE running the SDK bookend:' -ForegroundColor Cyan
Write-Host "  FOUNDRY_PROJECT_ENDPOINT=$projectEndpoint" -ForegroundColor Gray
Write-Host "  AGENT_ID=<copy from Foundry portal Agents tab after you build the agent>" -ForegroundColor Gray
Write-Host ''
Write-Host 'Auth pattern: keyless (DefaultAzureCredential). No keys in .env for L11.' -ForegroundColor Cyan
Write-Host '  The credential chain picks up your az login token at runtime.' -ForegroundColor Gray
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Open the Foundry portal at https://ai.azure.com/ -- New Foundry toggle ON.' -ForegroundColor Gray
Write-Host "  2. Switch to project: $ProjectName (under resource $FoundryName)." -ForegroundColor Gray
Write-Host "  3. One-time: Agents -> Traces -> Connect -> pick $AppInsightsName (enables trace export)." -ForegroundColor Gray
Write-Host '  4. Build the agent in the Agents tab. Copy the agent ID into demo\.env.' -ForegroundColor Gray
Write-Host '  5. Continue with the portal walkthrough per the lesson README.' -ForegroundColor Gray
Write-Host '  6. Run the SDK bookend: cd lessons\lesson-11\demo; python -m venv .venv; .venv\Scripts\Activate.ps1' -ForegroundColor Gray
Write-Host '             pip install -r requirements.txt; python lesson-11-agent-call.py' -ForegroundColor Gray
Write-Host '  7. When finished: .\Deploy-Lesson11-Infrastructure.ps1 -Cleanup' -ForegroundColor Gra