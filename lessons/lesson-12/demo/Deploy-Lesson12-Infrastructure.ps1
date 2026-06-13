#Requires -Version 7.0
<#
.SYNOPSIS
    Provisions / verifies the Azure infrastructure for AI-901 Lesson 12 --
    Build a Lightweight Client Application for an Agent.

.DESCRIPTION
    Lesson 12 calls the SAME agent built in Lesson 11 from a multi-turn Python
    client (lesson-12-agent-client.py). It needs a Foundry project with a
    tool-capable model and an existing agent to talk to.

    NEW FOUNDRY, NOT CLASSIC HUB. Same shape as L11 -- a Foundry AIServices
    resource owns the project; no separate Azure AI Hub.

    Two ways to run this script:

      * REUSE (default behavior when L11's resources still exist): point the
        client at the Lesson 11 project + agent. Pass -ReuseLesson11 to copy
        the L11 endpoint/agent into this lesson's .env guidance and skip
        re-provisioning. Cheapest and truest to the lesson narrative.

      * STANDALONE: provision a fresh rg-ai901-lesson12-demo with its own
        Foundry resource (S0), project, and gpt-4o deployment, then build the
        agent once in the portal (following the same steps as Lesson 11) and paste
        its ID. Use this when the L11 resource group has already been cleaned up.

    Resources provisioned in STANDALONE mode:

      * <FoundryName>         -- Foundry AIServices resource (S0, kind=AIServices)
      * <ProjectName>         -- Foundry project (owns the model + agent)
      * gpt-4o deployment     -- tool-capable base model (2024-11-20).
      * RBAC: Cognitive Services OpenAI User to the signed-in identity (keyless).

    Auth pattern: KEYLESS (DefaultAzureCredential). No keys in .env for L12.

    Cost: < $0.50 per learning session (reuse mode adds nothing).

.PARAMETER ResourceGroup
    Resource group. Default: rg-ai901-lesson12-demo.

.PARAMETER Location
    Azure region. Default: swedencentral.
    Supported values: swedencentral, japaneast, southindia, norwayeast,
    polandcentral, westus3, eastus2.

.PARAMETER FoundryName
    Foundry (AIServices) account name. Default: ai901-lesson12-foundry.
    Must be globally unique -- add a suffix if you see a name-conflict error.

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson12-project.

.PARAMETER ChatDeploymentName
    Tool-capable chat model deployment the agent rides on. Default: gpt-4o.

.PARAMETER ReuseLesson11
    Switch. Skip provisioning; print guidance to reuse the Lesson 11 project
    + agent directly.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.EXAMPLE
    .\Deploy-Lesson12-Infrastructure.ps1 -ReuseLesson11
    Reuse the Lesson 11 Foundry project + agent (recommended path).

.EXAMPLE
    .\Deploy-Lesson12-Infrastructure.ps1
    Stand up dedicated Lesson 12 infra, then build the agent in the portal.

.EXAMPLE
    .\Deploy-Lesson12-Infrastructure.ps1 -FoundryName ai901-lesson12-xyz
    Use a custom globally-unique Foundry resource name.

.NOTES
    Prerequisites:
      * Azure CLI (https://aka.ms/azurecli) -- run `az login` before this script.
      * Contributor + User Access Administrator on the target subscription, OR Owner.
    GUI fallback: Foundry portal at https://ai.azure.com (New Foundry ON).
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson12-demo',

    [Parameter()]
    [ValidateSet('swedencentral', 'japaneast', 'southindia', 'norwayeast',
                 'polandcentral', 'westus3', 'eastus2')]
    [string]$Location = 'swedencentral',

    [Parameter()]
    # Must be globally unique. Change the suffix if you get a name-conflict error.
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson12-foundry',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson12-project',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4o',

    [Parameter()]
    [switch]$ReuseLesson11,

    [Parameter()]
    [switch]$Cleanup
)

# ----------------------------------------------------------------------------
# Helpers (glyphs carry meaning, not color alone -- accessible reading)
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
    $glyph, $color = switch ($Kind) {
        'OK'   { '[ OK ]', 'Green'  }
        'SKIP' { '[SKIP]', 'Yellow' }
        'WAIT' { '[WAIT]', 'Cyan'   }
        'FAIL' { '[FAIL]', 'Red'    }
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
    Write-Status FAIL 'Not signed in. Run: az login'
    exit 1
}
Write-Status OK "Signed in as $($acct.user.name) -- subscription: $($acct.name)"

# ----------------------------------------------------------------------------
# Reuse branch -- point Lesson 12 at the Lesson 11 project + agent
# ----------------------------------------------------------------------------
if ($ReuseLesson11) {
    Write-Section 'Reuse mode: Lesson 11 project + agent'
    $l11Rg      = 'rg-ai901-lesson11-demo'
    $l11Foundry = 'ai901-lesson11-foundry'
    $l11Project = 'ai901-lesson11-project'
    $ep = & az cognitiveservices account show -g $l11Rg -n $l11Foundry --query 'properties.endpoint' -o tsv 2>$null
    if (-not $ep) {
        Write-Status FAIL "Lesson 11 resource $l11Foundry not found in $l11Rg."
        Write-Status WAIT 'Run Deploy-Lesson11-Infrastructure.ps1 first, OR run this script without -ReuseLesson11 to provision dedicated L12 infra.'
        exit 1
    }
    $projectEndpoint = ($ep.TrimEnd('/') -replace 'cognitiveservices\.azure\.com','services.ai.azure.com') + "/api/projects/$l11Project"
    Write-Status OK 'Lesson 11 resources found -- reuse them for Lesson 12.'
    Write-Host ''
    Write-Host 'Paste into demo\.env BEFORE running the Lesson 12 client:' -ForegroundColor Cyan
    Write-Host "  FOUNDRY_PROJECT_ENDPOINT=$projectEndpoint" -ForegroundColor Gray
    Write-Host '  AGENT_ID=<the contoso-docs-assistant agent ID from the Foundry Agents tab>' -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Auth pattern: keyless (DefaultAzureCredential). No keys in .env.' -ForegroundColor Cyan
    return
}

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
            Write-Status OK 'Delete submitted (async). Resources gone in ~5-10 min.'
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
        Invoke-Az -Args @('group','create','--name',$ResourceGroup,'--location',$Location,
            '--tags','purpose=ai901-lesson12-demo','owner=ai901-student','cleanup=true',
            '--output','none') | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry (AIServices) account (idempotent)
# ----------------------------------------------------------------------------
Write-Section "Foundry resource: $FoundryName (kind=AIServices, S0)"

$existingAcct = & az cognitiveservices account show `
    --resource-group $ResourceGroup --name $FoundryName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP 'Foundry resource already exists.'
} else {
    # Idempotency across deploy -> cleanup -> deploy: a same-named account deleted
    # recently sits in a SOFT-DELETED state and blocks recreation. The custom-subdomain
    # reservation is GLOBAL -- purge it in its original location before recreating.
    $ghost = & az cognitiveservices account list-deleted -o json 2>$null |
        ConvertFrom-Json | Where-Object { $_.name -eq $FoundryName } | Select-Object -First 1
    if ($ghost) {
        $ghostLoc = if ($ghost.location) { $ghost.location } else { ($ghost.id -split '/locations/')[1].Split('/')[0] }
        $ghostRg  = ($ghost.id -split '/resourceGroups/')[1].Split('/')[0]
        Write-Status WAIT "Purging soft-deleted $FoundryName in $ghostLoc (global subdomain reservation)..."
        & az cognitiveservices account purge --location $ghostLoc --resource-group $ghostRg --name $FoundryName --output none 2>$null
        Start-Sleep -Seconds 5   # let the purge settle before recreating
    }
    if ($PSCmdlet.ShouldProcess($FoundryName, 'Create AIServices account')) {
        Write-Status WAIT "Creating $FoundryName (this can take 30-60s)..."
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--resource-group', $ResourceGroup,
            '--name', $FoundryName,
            '--kind', 'AIServices',
            '--sku', 'S0',
            '--location', $Location,
            '--custom-domain', $FoundryName,
            '--yes',
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Foundry resource created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry project (child of the resource)
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
            '--name', $FoundryName,
            '--resource-group', $ResourceGroup,
            '--project-name', $ProjectName,
            '--output','none'
        ) | Out-Null
        Write-Status OK 'Foundry project created.'
    }
}

# ----------------------------------------------------------------------------
# Model deployment: gpt-4o (tool-capable base model for the agent)
# ----------------------------------------------------------------------------
$ChatModelName    = 'gpt-4o'
$ChatModelVersion = '2024-11-20'   # GA, function-calling supported

Write-Section "Model deployment: $ChatDeploymentName -> $ChatModelName ($ChatModelVersion)"

$existingChat = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ChatDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingChat) {
    Write-Status SKIP 'Chat deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ChatDeploymentName, "Create $ChatModelName deployment")) {
        Write-Status WAIT "Creating $ChatDeploymentName -> $ChatModelName (30-90s)..."
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
            Write-Host 'Most likely cause: gpt-4o Standard quota exhausted in this region.' -ForegroundColor Yellow
            Write-Host 'Remediation: request quota at https://aka.ms/oai/quotaincrease or try -Location japaneast.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Chat deployment created.'
    }
}

# ----------------------------------------------------------------------------
# RBAC: Cognitive Services OpenAI User (keyless inference)
# ----------------------------------------------------------------------------
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
# Outputs
# ----------------------------------------------------------------------------
Write-Section 'Deployment complete'

$foundryEp       = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$projectEndpoint = ($foundryEp.TrimEnd('/') -replace 'cognitiveservices\.azure\.com','services.ai.azure.com') + "/api/projects/$ProjectName"

$result = [pscustomobject]@{
    SubscriptionName = $acct.name
    ResourceGroup    = $ResourceGroup
    Region           = $Location
    FoundryResource  = $FoundryName
    FoundryProject   = $ProjectName
    ProjectEndpoint  = $projectEndpoint
    ChatModel        = "$ChatModelName ($ChatModelVersion, GlobalStandard, cap 10) -- tool-capable"
    AuthPattern      = 'Keyless (DefaultAzureCredential)'
    PortalUrl        = "https://portal.azure.com/#resource/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/overview"
}
$result | Format-List

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Build the agent ONCE: Foundry portal -> Agents -> build contoso-docs-assistant' -ForegroundColor Gray
Write-Host '     (same steps as in Lesson 11), then copy its agent ID.' -ForegroundColor Gray
Write-Host '  2. Paste into demo\.env:' -ForegroundColor Gray
Write-Host "       FOUNDRY_PROJECT_ENDPOINT=$projectEndpoint" -ForegroundColor Gray
Write-Host '       AGENT_ID=<agent ID from the Agents tab>' -ForegroundColor Gray
Write-Host '  3. cd lessons\lesson-12\demo; python -m venv .venv; .venv\Scripts\Activate.ps1' -ForegroundColor Gray
Write-Host '     pip install -r requirements.txt; python lesson-12-agent-client.py' -ForegroundColor Gray
Write-Host '  4. When finished: .\Deploy-Lesson12-Infrastructure.ps1 -Cleanup' -ForegroundColor Gray
Write-Host ''

return $result
