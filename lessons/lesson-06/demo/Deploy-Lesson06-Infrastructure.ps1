<#
.SYNOPSIS
    Provisions (or tears down) the Azure infrastructure for the AI-901 Lesson 06 demo --
    Computer Vision and Image-Generation Concepts (Vision Studio + Foundry multimodal
    chat + image generation + Python SDK bookend).

.DESCRIPTION
    Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video).
    Lesson 06 covers Azure AI Vision (image analysis, OCR, face detection), multimodal
    large language models (vision-capable chat), and image generation (gpt-image-1.5).

    Resources provisioned in rg-ai901-lesson06-demo (East US 2):

      * ai901-lesson06-vision   -- singleton Azure AI Vision (kind=ComputerVision,
                                    F0 free tier) for Vision Studio and the Python
                                    SDK bookend.
      * ai901-lesson06-foundry  -- Foundry AIServices resource (S0) hosting:
                                      - gpt-4o deployment (multimodal vision chat)
                                      - gpt-image-1.5 deployment (image generation)
      * ai901-lesson06-project  -- Foundry project for the chat playground.

    Cost: < $0.50 per session. Vision F0 is free. Foundry S0 + model deployments
    are pay-per-call only -- no idle charges. Run -Cleanup promptly after practice
    to keep it that way.

    IMPORTANT NOTE ON VISION REGION:
    The singleton Vision resource is created in East US (NOT East US 2). The Caption
    visual feature is region-gated; East US 2 returns "feature not supported in this
    region." East US supports Caption and is within the same latency band.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson06-demo.

.PARAMETER Location
    Primary Azure region for the Foundry resource. Default: eastus2.

.PARAMETER FoundryName
    Azure resource name for the Foundry account. Default: ai901-lesson06-foundry.

.PARAMETER VisionName
    Singleton Azure AI Vision resource name. Default: ai901-lesson06-vision.

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson06-project.

.PARAMETER ChatDeploymentName
    Name of the multimodal chat deployment. Default: gpt-4o.

.PARAMETER ImageDeploymentName
    Name of the image-generation deployment. Default: gpt-image-1-5.

.PARAMETER Cleanup
    Switch. Deletes the resource group and exits.

.PARAMETER WhatIf
    Dry-run. Prints what would happen without making Azure changes.

.EXAMPLE
    .\Deploy-Lesson06-Infrastructure.ps1
    Idempotent deploy with default names. Safe to rerun.

.EXAMPLE
    .\Deploy-Lesson06-Infrastructure.ps1 -Cleanup
    Async delete the resource group and every resource inside it.

.NOTES
    Author:        Tim Warner
    Created:       2026-05-29
    Tested:        PowerShell 7.4+ on Windows 11; Azure CLI 2.51+
    Cost estimate: < $0.50 per session.
    Requirements:  Azure CLI 2.51+, signed in (az login).

    Resource names default to "ai901-lessonNN-..." patterns. They must be globally
    unique in Azure. Use -FoundryName / -VisionName overrides if you hit a conflict.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson06-demo',

    [Parameter()]
    [ValidateSet('eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus',
                 'northcentralus', 'southcentralus', 'westcentralus')]
    [string]$Location = 'eastus2',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson06-foundry',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$VisionName = 'ai901-lesson06-vision',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson06-project',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4o',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ImageDeploymentName = 'gpt-image-1-5',

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
            '--tags', 'purpose=ai901-lesson06-demo', 'owner=ai901-student', 'cleanup=true',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry AIServices resource (multimodal chat + image generation)
# ----------------------------------------------------------------------------

Write-Section "Foundry AIServices resource: $FoundryName"

$existingAcct = & az cognitiveservices account show `
    --name $FoundryName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingAcct) {
    Write-Status SKIP 'Foundry resource already exists.'
} else {
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
        Write-Status OK 'Project management enabled.'
    }
} else {
    Write-Status SKIP 'Project management already enabled.'
}

# ----------------------------------------------------------------------------
# Foundry project
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
# Singleton Azure AI Vision (kind=ComputerVision, F0) -- Vision Studio surface
# ----------------------------------------------------------------------------
# Vision Studio at portal.vision.cognitive.azure.com targets a singleton
# ComputerVision resource by resource picker. Image analysis, OCR, face
# detection, and the Python SDK bookend all use this resource.
#
# IMPORTANT: Vision MUST go in East US (not East US 2). The Caption visual
# feature is region-gated and East US 2 returns "feature not supported in
# this region." East US, France Central, West Europe, and a few others support
# Caption. East US is chosen here to stay in the same latency band.

Write-Section "Singleton Azure AI Vision: $VisionName (kind=ComputerVision, F0)"

$existingVision = & az cognitiveservices account show `
    --name $VisionName --resource-group $ResourceGroup --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingVision) {
    Write-Status SKIP 'Vision resource already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($VisionName, 'Create Vision (ComputerVision F0) resource')) {
        Invoke-Az -Args @(
            'cognitiveservices','account','create',
            '--name', $VisionName,
            '--resource-group', $ResourceGroup,
            '--kind', 'ComputerVision',
            '--sku', 'F0',
            '--location', 'eastus',
            '--custom-domain', $VisionName,
            '--assign-identity',
            '--yes',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Vision resource created in East US (Caption-supported region).'
    }
}

# ----------------------------------------------------------------------------
# Model deployment: gpt-4o (multimodal vision chat)
# ----------------------------------------------------------------------------

Write-Section "Model deployment: $ChatDeploymentName -> gpt-4o"

$existingChat = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ChatDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingChat) {
    Write-Status SKIP 'Chat (multimodal) deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ChatDeploymentName, 'Create multimodal chat deployment')) {
        Write-Status WAIT "Creating $ChatDeploymentName (this can take 30-90s)..."
        $deployOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $ChatDeploymentName `
            --model-name 'gpt-4o' `
            --model-version '2024-11-20' `
            --model-format 'OpenAI' `
            --sku-capacity 10 `
            --sku-name 'Standard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Chat deployment failed: $deployOutput"
            Write-Host ''
            Write-Host 'Most likely cause: gpt-4o Standard quota exhausted in this region.' -ForegroundColor Yellow
            Write-Host 'Quick remediation: request quota at https://aka.ms/oai/quotaincrease' -ForegroundColor Yellow
            Write-Host '  OR swap to gpt-4.1-mini -- change ChatDeploymentName and model-name above.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Chat (multimodal) deployment created.'
    }
}

# ----------------------------------------------------------------------------
# Model deployment: gpt-image-1.5 (image generation)
# ----------------------------------------------------------------------------

Write-Section "Model deployment: $ImageDeploymentName -> gpt-image-1.5"

$existingImage = & az cognitiveservices account deployment show `
    --resource-group $ResourceGroup --name $FoundryName `
    --deployment-name $ImageDeploymentName --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingImage) {
    Write-Status SKIP 'Image-generation deployment already exists.'
} else {
    if ($PSCmdlet.ShouldProcess($ImageDeploymentName, 'Create image-generation deployment')) {
        Write-Status WAIT "Creating $ImageDeploymentName (this can take 30-90s)..."
        $imgOutput = & az cognitiveservices account deployment create `
            --resource-group $ResourceGroup `
            --name $FoundryName `
            --deployment-name $ImageDeploymentName `
            --model-name 'gpt-image-1.5' `
            --model-version '2025-12-16' `
            --model-format 'OpenAI' `
            --sku-capacity 1 `
            --sku-name 'GlobalStandard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Image deployment failed: $imgOutput"
            Write-Host ''
            Write-Host 'Most likely cause: gpt-image-1.5 quota or capacity issue.' -ForegroundColor Yellow
            Write-Host 'Quick remediation: swap to gpt-image-1-mini -- edit model-name above.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Image-generation deployment created.'
    }
}

# ----------------------------------------------------------------------------
# Collect outputs
# ----------------------------------------------------------------------------

Write-Section 'Collecting deployment metadata'

$foundryEp   = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$visionEp    = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$VisionName,'--query','properties.endpoint','-o','tsv')) -join ''
$identityOid = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','identity.principalId','-o','tsv')) -join ''
$signedInOid = (Invoke-Az -Args @('ad','signed-in-user','show','--query','id','-o','tsv')) -join ''
$visionKey   = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$VisionName,'--query','key1','-o','tsv')) -join ''
$foundryKey  = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$FoundryName,'--query','key1','-o','tsv')) -join ''
$visionLast4  = if ($visionKey.Length -ge 4)  { $visionKey.Substring($visionKey.Length - 4) }   else { 'n/a' }
$foundryLast4 = if ($foundryKey.Length -ge 4) { $foundryKey.Substring($foundryKey.Length - 4) } else { 'n/a' }

# ----------------------------------------------------------------------------
# Smoke test: chat completion against the multimodal deployment
# ----------------------------------------------------------------------------

Write-Section 'Smoke test: chat completion against multimodal deployment'

$body = @{
    messages = @(@{ role = 'user'; content = 'Reply with the single word OK.' })
    max_completion_tokens = 8
} | ConvertTo-Json -Compress
$uri = "${foundryEp}openai/deployments/$ChatDeploymentName/chat/completions?api-version=2024-10-21"
try {
    $smokeObj = Invoke-RestMethod -Method POST -Uri $uri `
        -Headers @{ 'api-key' = $foundryKey; 'Content-Type' = 'application/json' } `
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
    FoundryResource     = $FoundryName
    FoundryProject      = $ProjectName
    FoundryEndpoint     = $foundryEp
    VisionResource      = $VisionName
    VisionEndpoint      = $visionEp
    ChatDeployment      = $ChatDeploymentName
    ChatModel           = 'gpt-4o (2024-11-20, Standard, cap 10)'
    ImageDeployment     = $ImageDeploymentName
    ImageModel          = 'gpt-image-1.5 (2025-12-16, GlobalStandard, cap 1)'
    ManagedIdentityOid  = $identityOid
    VisionKey1Last4     = $visionLast4
    FoundryKey1Last4    = $foundryLast4
    FoundryPortalUrl    = 'https://ai.azure.com/'
    VisionStudioUrl     = 'https://portal.vision.cognitive.azure.com/'
}

$result | Format-List

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Open Vision Studio at https://portal.vision.cognitive.azure.com/' -ForegroundColor Gray
Write-Host "  2. Pick the Vision resource: $VisionName" -ForegroundColor Gray
Write-Host '  3. Open the Foundry portal at https://ai.azure.com/ for the chat and image-gen demos.' -ForegroundColor Gray
Write-Host "  4. Switch to project: $ProjectName" -ForegroundColor Gray
Write-Host '  5. Populate demo/.env with VISION_ENDPOINT and VISION_KEY for the Python SDK bookend.' -ForegroundColor Gray
Write-Host "  6. When done: .\Deploy-Lesson06-Infrastructure.ps1 -Cleanup" -ForegroundColor Gray
Write-Host ''

return $result
