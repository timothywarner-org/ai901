<#
.SYNOPSIS
    Provisions (or tears down) the Azure infrastructure for the AI-901 Lesson 05 demo --
    Text Analysis and Speech Concepts (Azure AI Language + Azure AI Speech + Foundry
    chat for the classic-vs-generative NLP comparison).

.DESCRIPTION
    Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video).
    Lesson 05 covers Azure AI Language (NER / sentiment / key phrases / summarization /
    PII), Azure AI Speech (STT / TTS / SSML / diarization / Fast Transcription), and
    the NLP continuum (classic prebuilt API vs. generative model).

    A single Microsoft Foundry resource (kind = AIServices) is the multi-service umbrella
    that exposes Azure AI Language, Azure AI Translator, and Azure AI Speech as
    "Foundry Tools" in the Foundry portal at https://ai.azure.com. One resource therefore
    covers every Lesson 05 service without requiring separate Language or Speech resources.
    This is also the Microsoft-recommended consolidation pattern for AI-901.

    In addition, two singleton resources are provisioned for the portal studio surfaces:
      * A singleton Azure AI Language (TextAnalytics, F0) for Language Studio.
      * A singleton Azure AI Speech (SpeechServices, F0) for Speech Studio.

    The script is fully idempotent. Re-running it after a partial failure will detect
    existing resources and skip them rather than erroring. Re-running with -Cleanup
    deletes the resource group asynchronously.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson05-demo.

.PARAMETER Location
    Primary Azure region. Default: eastus2.

.PARAMETER LocationFallback
    Region to retry if the primary region rejects the model deployment due to quota.
    Default: eastus.

.PARAMETER FoundryName
    Azure resource name for the Foundry account. Must be globally unique.
    Default: ai901-lesson05-foundry.

.PARAMETER LanguageName
    Singleton Azure AI Language resource name. Default: ai901-lesson05-language.

.PARAMETER SpeechName
    Singleton Azure AI Speech resource name. Default: ai901-lesson05-speech.

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson05-project.

.PARAMETER ModelDeploymentName
    Name of the model deployment as it appears in the Foundry portal.
    AI-901 tip: the deployment name is NOT the same as the model name -- client
    code references the deployment name. Default: gpt-4-1-mini.

.PARAMETER Cleanup
    Switch. When present, deletes the resource group and exits.

.PARAMETER WhatIf
    Standard PowerShell common parameter. Prints what would happen without
    making any Azure changes.

.EXAMPLE
    .\Deploy-Lesson05-Infrastructure.ps1
    Deploys everything with default names. Idempotent -- safe to rerun.

.EXAMPLE
    .\Deploy-Lesson05-Infrastructure.ps1 -Cleanup
    Deletes the resource group and every resource inside it. Async, no wait.

.EXAMPLE
    .\Deploy-Lesson05-Infrastructure.ps1 -WhatIf
    Dry-runs the deployment plan. No Azure calls are made.

.NOTES
    Author:        Tim Warner
    Created:       2026-05-27
    Tested:        PowerShell 7.4+ on Windows 11; Azure CLI 2.51+
    Cost estimate: < $0.50 per session (AIServices is pay-per-use; gpt-4.1-mini
                   at fractions of a cent per chat turn, plus pennies for Speech
                   and Language calls).
    Requirements:  Azure CLI 2.51+, signed in (az login).

    Resource names default to "ai901-lessonNN-..." patterns. They must be globally
    unique in Azure. Add -FoundryName / -LanguageName / -SpeechName overrides if
    you hit a naming conflict.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson05-demo',

    [Parameter()]
    [ValidateSet('eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus',
                 'northcentralus', 'southcentralus', 'westcentralus')]
    [string]$Location = 'eastus2',

    [Parameter()]
    [ValidateSet('eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus',
                 'northcentralus', 'southcentralus', 'westcentralus')]
    [string]$LocationFallback = 'eastus',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson05-foundry',

    # Singleton Azure AI Language resource (kind=TextAnalytics, F0 free tier).
    # Backs the MS Learn "Try it out" widget and classic Language Studio.
    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$LanguageName = 'ai901-lesson05-language',

    # Singleton Azure AI Speech resource (kind=SpeechServices, F0 free tier).
    # Backs Speech Studio (speech.microsoft.com) for STT, TTS, SSML, Voice Gallery.
    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$SpeechName = 'ai901-lesson05-speech',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson05-project',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ModelDeploymentName = 'gpt-4-1-mini',

    [Parameter()]
    [switch]$Cleanup
)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

# Pretty-printed section header. Width-fixed at 78 cols to fit a default terminal.
function Write-Section {
    param([string]$Title)
    $bar = ('=' * 78)
    Write-Host ''
    Write-Host $bar -ForegroundColor Cyan
    Write-Host (' ' + $Title) -ForegroundColor Cyan
    Write-Host $bar -ForegroundColor Cyan
}

# Single status line with a glyph prefix -- uses ASCII characters for portability.
function Write-Status {
    param(
        [ValidateSet('OK', 'SKIP', 'WAIT', 'FAIL')][string]$Kind,
        [string]$Message
    )
    $glyph, $color = switch ($Kind) {
        'OK'   { '[ OK ]', 'Green'   }
        'SKIP' { '[SKIP]', 'Yellow'  }
        'WAIT' { '[WAIT]', 'Cyan'    }
        'FAIL' { '[FAIL]', 'Red'     }
    }
    Write-Host "$glyph $Message" -ForegroundColor $color
}

# Wraps `az` and throws a clean exception on non-zero exit. Treating the CLI
# as a function rather than a bag of strings is the biggest reliability upgrade
# in any PowerShell-meets-az script.
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

$rpState = (Invoke-Az -Args @('provider','show','--namespace','Microsoft.CognitiveServices','--query','registrationState','-o','tsv')) -join ''
if ($rpState -ne 'Registered') {
    Write-Status WAIT "Registering Microsoft.CognitiveServices provider..."
    Invoke-Az -Args @('provider','register','--namespace','Microsoft.CognitiveServices') | Out-Null
}
Write-Status OK 'Microsoft.CognitiveServices provider registered'

# ----------------------------------------------------------------------------
# Cleanup branch
# ----------------------------------------------------------------------------

if ($Cleanup) {
    Write-Section "Cleanup: deleting resource group $ResourceGroup"
    $exists = (Invoke-Az -Args @('group','exists','--name',$ResourceGroup,'-o','tsv')) -join ''
    if ($exists -eq 'true') {
        if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Delete resource group')) {
            Invoke-Az -Args @('group','delete','--name',$ResourceGroup,'--yes','--no-wait') | Out-Null
            Write-Status OK "Delete submitted (async). Resources will be gone in ~5-10 min."
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
    Write-Status SKIP "Resource group already exists."
} else {
    if ($PSCmdlet.ShouldProcess($ResourceGroup, 'Create resource group')) {
        Invoke-Az -Args @(
            'group','create',
            '--name', $ResourceGroup,
            '--location', $Location,
            '--tags', 'purpose=ai901-lesson05-demo', 'owner=ai901-student', 'cleanup=true',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK "Resource group created."
    }
}

# ----------------------------------------------------------------------------
# Foundry AIServices resource (idempotent)
# ----------------------------------------------------------------------------
# This single resource exposes Azure AI Language (NER, sentiment, key phrases,
# summarization, PII), Azure AI Speech (STT, TTS, SSML, Fast Transcription,
# diarization), Azure AI Translator, and model deployment -- one umbrella,
# three exam services. That is why AIServices is the right kind here.

Write-Section "Foundry AIServices resource: $FoundryName"

$existingAcct = & az cognitiveservices account show `
    --name $FoundryName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP "Foundry resource already exists."
} else {
    if ($PSCmdlet.ShouldProcess($FoundryName, 'Create Foundry AIServices resource')) {
        # --custom-domain is REQUIRED for Foundry project support and for
        # Microsoft Entra ID auth. --assign-identity costs nothing and enables
        # keyless auth for learners who want to explore beyond key auth.
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
        Write-Status OK "Foundry resource created."
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
        Write-Status OK "Project management enabled."
    }
} else {
    Write-Status SKIP "Project management already enabled."
}

# ----------------------------------------------------------------------------
# Foundry project (idempotent)
# ----------------------------------------------------------------------------

Write-Section "Foundry project: $ProjectName"

$existingProj = & az cognitiveservices account project show `
    --name $FoundryName --resource-group $ResourceGroup `
    --project-name $ProjectName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingProj) {
    Write-Status SKIP "Foundry project already exists."
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
        Write-Status OK "Foundry project created."
    }
}

# ----------------------------------------------------------------------------
# Singleton Azure AI Language (TextAnalytics, F0) -- portal studio surface
# ----------------------------------------------------------------------------
# The MS Learn doc pages for Language (NER, sentiment, key phrases, PII) ship
# an inline "Try it out" widget that targets a singleton TextAnalytics resource
# by resource picker. That widget is the lowest-friction portal surface.
# F0 free tier means $0 for the session.

Write-Section "Singleton Azure AI Language: $LanguageName (kind=TextAnalytics, F0)"

$existingLang = & az cognitiveservices account show `
    --name $LanguageName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingLang) {
    Write-Status SKIP "Language resource already exists."
} else {
    if ($PSCmdlet.ShouldProcess($LanguageName, 'Create Language (TextAnalytics F0) resource')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--name', $LanguageName,
            '--resource-group', $ResourceGroup,
            '--kind', 'TextAnalytics',
            '--sku', 'F0',
            '--location', $Location,
            '--custom-domain', $LanguageName,
            '--assign-identity',
            '--yes',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK "Language resource created."
    }
}

# ----------------------------------------------------------------------------
# Singleton Azure AI Speech (SpeechServices, F0) -- portal studio surface
# ----------------------------------------------------------------------------
# Speech Studio (speech.microsoft.com) targets a singleton SpeechServices
# resource by resource picker. Real-time STT, Fast Transcription with
# diarization, Voice Gallery, and SSML editor all live in Speech Studio.
# F0 free tier covers a single session many times over.

Write-Section "Singleton Azure AI Speech: $SpeechName (kind=SpeechServices, F0)"

$existingSpeech = & az cognitiveservices account show `
    --name $SpeechName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingSpeech) {
    Write-Status SKIP "Speech resource already exists."
} else {
    if ($PSCmdlet.ShouldProcess($SpeechName, 'Create Speech (SpeechServices F0) resource')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--name', $SpeechName,
            '--resource-group', $ResourceGroup,
            '--kind', 'SpeechServices',
            '--sku', 'F0',
            '--location', $Location,
            '--custom-domain', $SpeechName,
            '--assign-identity',
            '--yes',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK "Speech resource created."
    }
}

# ----------------------------------------------------------------------------
# Model deployment (idempotent, with fallback guidance)
# ----------------------------------------------------------------------------
# gpt-4.1-mini, Standard SKU, capacity 10.
# AI-901 tip: deployment name and model name are NOT the same; the API
# uses the deployment name. That is what ModelDeploymentName captures here.

Write-Section "Model deployment: $ModelDeploymentName -> gpt-4.1-mini"

$modelName    = 'gpt-4.1-mini'
$modelVersion = '2025-04-14'
$modelSku     = 'Standard'
$modelCap     = 10

$existingDep = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ModelDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingDep) {
    Write-Status SKIP "Model deployment already exists."
} else {
    if ($PSCmdlet.ShouldProcess($ModelDeploymentName, 'Create model deployment')) {
        Write-Status WAIT "Creating $ModelDeploymentName (this can take 30-90s)..."
        $deployOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $ModelDeploymentName `
            --model-name $modelName `
            --model-version $modelVersion `
            --model-format 'OpenAI' `
            --sku-capacity $modelCap `
            --sku-name $modelSku `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Model deployment failed: $deployOutput"
            Write-Host ''
            Write-Host "Most likely cause: gpt-4.1-mini Standard quota exhausted in $Location." -ForegroundColor Yellow
            Write-Host "Quick remediation:" -ForegroundColor Yellow
            Write-Host "  1. Run this script with -Cleanup, then rerun with -Location $LocationFallback" -ForegroundColor Yellow
            Write-Host "  2. OR request quota at https://aka.ms/oai/quotaincrease" -ForegroundColor Yellow
            Write-Host "  3. OR swap to gpt-4.1-nano (GlobalStandard) -- edit the modelName variable above" -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK "Model deployment created."
    }
}

# ----------------------------------------------------------------------------
# Collect outputs
# ----------------------------------------------------------------------------

Write-Section 'Collecting deployment metadata'

$endpoint     = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$identityOid  = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','identity.principalId','-o','tsv')) -join ''
$raiPolicy    = (Invoke-Az -Args @('cognitiveservices','account','deployment','show','-g',$ResourceGroup,'-n',$FoundryName,'--deployment-name',$ModelDeploymentName,'--query','properties.raiPolicyName','-o','tsv')) -join ''
$signedInOid  = (Invoke-Az -Args @('ad','signed-in-user','show','--query','id','-o','tsv')) -join ''
$key1         = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$FoundryName,'--query','key1','-o','tsv')) -join ''
$key1Last4    = if ($key1.Length -ge 4) { $key1.Substring($key1.Length - 4) } else { 'n/a' }

$languageEndpoint  = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$LanguageName,'--query','properties.endpoint','-o','tsv')) -join ''
$languageKey1      = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$LanguageName,'--query','key1','-o','tsv')) -join ''
$languageKey1Last4 = if ($languageKey1.Length -ge 4) { $languageKey1.Substring($languageKey1.Length - 4) } else { 'n/a' }

$speechEndpoint    = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$SpeechName,'--query','properties.endpoint','-o','tsv')) -join ''
$speechKey1        = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$SpeechName,'--query','key1','-o','tsv')) -join ''
$speechKey1Last4   = if ($speechKey1.Length -ge 4) { $speechKey1.Substring($speechKey1.Length - 4) } else { 'n/a' }

# ----------------------------------------------------------------------------
# Smoke test: chat completion against the new deployment
# ----------------------------------------------------------------------------

Write-Section 'Smoke test: chat completion against the new deployment'

# Proves three things in one round-trip:
#   1. The endpoint is reachable.
#   2. The key works.
#   3. The deployment is in a callable state.
$body = @{
    messages = @(@{ role = 'user'; content = 'Reply with the single word OK.' })
    max_completion_tokens = 8
} | ConvertTo-Json -Compress

$uri = "${endpoint}openai/deployments/$ModelDeploymentName/chat/completions?api-version=2024-10-21"
try {
    $smokeObj = Invoke-RestMethod -Method POST -Uri $uri `
        -Headers @{ 'api-key' = $key1; 'Content-Type' = 'application/json' } `
        -Body $body -ErrorAction Stop
    if ($smokeObj.choices) {
        Write-Status OK "Smoke test passed (HTTP 200; model id: $($smokeObj.model))."
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
    SubscriptionId      = $acct.id
    ResourceGroup       = $ResourceGroup
    Region              = $Location

    # Singleton Language (portal primary for NER / sentiment / PII)
    LanguageResource    = $LanguageName
    LanguageEndpoint    = $languageEndpoint
    LanguageKey1Last4   = $languageKey1Last4
    LanguageStudioUrl   = 'https://language.cognitive.azure.com/'

    # Singleton Speech (portal primary for STT / TTS / SSML / diarization)
    SpeechResource      = $SpeechName
    SpeechEndpoint      = $speechEndpoint
    SpeechKey1Last4     = $speechKey1Last4
    SpeechStudioUrl     = 'https://speech.microsoft.com/'

    # Foundry (chat playground for generative sentiment comparison)
    FoundryResource     = $FoundryName
    FoundryProject      = $ProjectName
    FoundryEndpoint     = $endpoint
    DeploymentName      = $ModelDeploymentName
    ModelName           = $modelName
    ModelVersion        = $modelVersion
    RaiPolicy           = $raiPolicy
    ManagedIdentityOid  = $identityOid
    FoundryKey1Last4    = $key1Last4
    FoundryPortalUrl    = 'https://ai.azure.com/'
}

$result | Format-List

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Language Studio  -- https://language.cognitive.azure.com/' -ForegroundColor Gray
Write-Host "     (resource picker: $LanguageName)" -ForegroundColor Gray
Write-Host '  2. Speech Studio    -- https://speech.microsoft.com/' -ForegroundColor Gray
Write-Host "     (resource picker: $SpeechName)" -ForegroundColor Gray
Write-Host '  3. Foundry portal   -- https://ai.azure.com/' -ForegroundColor Gray
Write-Host "     (project: $ProjectName, deployment: $ModelDeploymentName)" -ForegroundColor Gray
Write-Host '  4. Python SDK bookend -- see demo/README.md for setup steps.' -ForegroundColor Gray
Write-Host "  5. When done: .\Deploy-Lesson05-Infrastructure.ps1 -Cleanup" -ForegroundColor Gray
Write-Host ''

return $result
