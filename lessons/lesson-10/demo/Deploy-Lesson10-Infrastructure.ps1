<#
.SYNOPSIS
    Provisions (or tears down) the Azure infrastructure for the AI-901 Lesson 10 demo --
    Build a Lightweight Chat Client with the Foundry SDK (the all-code lesson of
    Domain 2).

.DESCRIPTION
    Course: Exam AI-901 -- Microsoft Azure AI Fundamentals (Video).
    Lesson 10 is the all-code lesson of Domain 2. The entire lesson is Python SDK:
    (1) bootstrap + keyless auth, (2) chat completion + read-send-print loop,
    (3) streaming for perceived speed, (4) Python SDK closer plus RBAC
    failure-to-success demo.

    NEW FOUNDRY, NOT CLASSIC HUB. Same architectural shape as L09 -- a Foundry
    AIServices resource owns the project; no separate Azure AI Hub.
    The keyless-auth code in the first demo step uses DefaultAzureCredential against this project.

    Resources provisioned in rg-ai901-lesson10-demo (East US 2):

      * ai901-lesson10-foundry    -- Foundry AIServices resource (S0, kind=AIServices)
                                      with project management enabled.
                                      NOTE: this name must be globally unique -- change
                                      the default if it is already taken.
      * ai901-lesson10-project    -- Foundry project (child of the resource). Owns the
                                      gpt-4o deployment the chat client calls.
      * gpt-4o  deployment        -- the chat model the Python client talks to.
                                      gpt-4o 2024-11-20 is the tool-capable model this
                                      lesson needs for function calling and streaming.

    The RBAC failure-to-success demo (final step of the lesson):
      This lesson demonstrates the operational payoff of keyless auth by running the
      SAME chat.py from a second identity that lacks the Cognitive Services OpenAI
      User role -- 403 hits, then the role is assigned in the Azure portal, and
      rerunning succeeds.
      This script:
        * ASSIGNS Cognitive Services OpenAI User to the signed-in user
          (so the normal demo terminal works throughout the lesson).
        * DOES NOT assign the role to the teammate identity -- the NO-role state
          IS the demo.
        * Records the teammate UPN in the summary so you know what to use in the
          second terminal pane.

    What this script DOES NOT do:
      * Write code. The lesson IS the code -- learners build chat.py from an empty
        folder. The fabrikam-chat/ subfolder has the finished reference copy.
      * Stage the teammate identity. Set that up out-of-band with two cached
        az profiles or two browser-isolated sessions.

    Cost: < $0.50 per session. Foundry S0 + Standard model deployment are
    pay-per-token only. Run -Cleanup promptly after the demo.

.PARAMETER ResourceGroup
    Name of the resource group. Default: rg-ai901-lesson10-demo.

.PARAMETER Location
    Primary Azure region. Default: eastus2.

.PARAMETER FoundryName
    Azure resource name for the Foundry (AIServices) account.
    Default: ai901-lesson10-foundry. Must be globally unique -- change if taken.

.PARAMETER ProjectName
    Foundry project name. Default: ai901-lesson10-project.

.PARAMETER ChatDeploymentName
    Name of the chat deployment the Python client calls. Default: gpt-4o.

.PARAMETER TeammateUpn
    UPN of the teammate identity used in the RBAC failure-to-success demo.
    This script does NOT assign roles to the teammate -- just records the UPN
    in the summary so the post-deploy output documents who to sign in as in the
    second terminal pane.
    Default: demo-teammate@example.com.

.PARAMETER Cleanup
    Switch. Deletes the resource group (async), then exits.

.PARAMETER WhatIf
    Dry-run. Prints what would happen without making Azure changes.

.EXAMPLE
    .\Deploy-Lesson10-Infrastructure.ps1
    Idempotent deploy with default names. Safe to rerun.

.EXAMPLE
    .\Deploy-Lesson10-Infrastructure.ps1 -TeammateUpn "teammate@yourdomain.com"
    Idempotent deploy; records a custom teammate UPN in the summary.

.EXAMPLE
    .\Deploy-Lesson10-Infrastructure.ps1 -Cleanup
    Async delete the resource group and every resource inside it.

.NOTES
    Author:        Tim Warner
    Created:       2026-06-03
    Verified:      2026-06-03 against MS Learn Azure OpenAI keyless-auth docs and the
                   az cognitiveservices model list catalog (gpt-4o 2024-11-20 =
                   GenerallyAvailable, Standard, East US 2).
    GUI fallback:  Every Azure resource here is also reproducible via the Azure
                   portal (resource group -> + Create -> Foundry). See the lesson
                   README for the lesson flow.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-\.]{1,90}$')]
    [string]$ResourceGroup = 'rg-ai901-lesson10-demo',

    [Parameter()]
    [ValidateSet('eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus',
                 'northcentralus', 'southcentralus', 'westcentralus')]
    [string]$Location = 'eastus2',

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$FoundryName = 'ai901-lesson10-foundry',      # globally unique -- change if taken

    [Parameter()]
    [ValidatePattern('^[a-z][a-z0-9\-]{1,62}[a-z0-9]$')]
    [string]$ProjectName = 'ai901-lesson10-project',

    [Parameter()]
    [ValidatePattern('^[a-zA-Z0-9_\-]{1,64}$')]
    [string]$ChatDeploymentName = 'gpt-4o',

    [Parameter()]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$TeammateUpn = 'demo-teammate@example.com',

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
    # Glyphs carry the meaning (not color alone) -- accessibility for colorblind reading.
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
            '--tags', 'purpose=ai901-lesson10-demo', 'owner=ai901-student', 'cleanup=true',
            '--output', 'none'
        ) | Out-Null
        Write-Status OK 'Resource group created.'
    }
}

# ----------------------------------------------------------------------------
# Foundry AIServices resource (new Foundry -- the resource that owns the project)
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
        Write-Status OK 'Project management enabled (this is what makes it a Foundry resource).'
    }
} else {
    Write-Status SKIP 'Project management already enabled.'
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
# Model deployment: gpt-4o (DEPLOYMENT NAME == MODEL NAME)
# ----------------------------------------------------------------------------
# gpt-4o is used because it is the tool-capable model this lesson needs.
# gpt-4o 2024-11-20 deploys cleanly in East US 2 and matches what the
# chat completion call (including streaming) requires.

$ChatModelName = 'gpt-4o'
$ChatModelVersion = '2024-11-20'   # GA in East US 2

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
            --sku-name 'Standard' `
            --output none 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Status FAIL "Chat deployment failed: $deployOutput"
            Write-Host ''
            Write-Host "Most likely cause: $ChatModelName Standard quota exhausted in this region." -ForegroundColor Yellow
            Write-Host 'Quick remediation: request quota at https://aka.ms/oai/quotaincrease' -ForegroundColor Yellow
            Write-Host '  OR swap to GlobalStandard -- change --sku-name above.' -ForegroundColor Yellow
            exit 1
        }
        Write-Status OK 'Chat deployment created.'
    }
}

# ----------------------------------------------------------------------------
# RBAC: assign Cognitive Services OpenAI User to the signed-in user
# ----------------------------------------------------------------------------
# L10 is the keyless-auth lesson -- chat.py uses DefaultAzureCredential. The
# signed-in user needs the Cognitive Services OpenAI User role on the Foundry
# resource for the credential chain success path to call the model. The teammate
# identity intentionally does NOT get this role here -- the missing-role state
# IS the RBAC failure-to-success demo.

Write-Section 'RBAC: Cognitive Services OpenAI User on the Foundry resource (signed-in user only)'

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
    Write-Status SKIP 'Role assignment already in place for signed-in user.'
}

# Sanity check: confirm the teammate UPN does NOT already have the role.
# If it does, the "wrong role -> 403" demo will silently succeed instead of fail,
# and the operational-payoff moment is lost.
$teammateExisting = & az role assignment list `
    --assignee $TeammateUpn --scope $scope `
    --role 'Cognitive Services OpenAI User' `
    --query '[].id' -o tsv 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($teammateExisting -join ''))) {
    Write-Status FAIL "TEAMMATE WARNING: $TeammateUpn already has Cognitive Services OpenAI User."
    Write-Host '  RBAC failure-to-success demo will not produce a 403.' -ForegroundColor Yellow
    Write-Host "  Revoke before the demo: az role assignment delete --assignee $TeammateUpn --scope $scope --role 'Cognitive Services OpenAI User'" -ForegroundColor Yellow
} else {
    Write-Status OK "Teammate $TeammateUpn confirmed has NO role (RBAC demo will produce 403 as intended)."
}

# ----------------------------------------------------------------------------
# Collect outputs
# ----------------------------------------------------------------------------

Write-Section 'Collecting deployment metadata'

$foundryEp    = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','properties.endpoint','-o','tsv')) -join ''
$identityOid  = (Invoke-Az -Args @('cognitiveservices','account','show','-g',$ResourceGroup,'-n',$FoundryName,'--query','identity.principalId','-o','tsv')) -join ''
$foundryKey   = (Invoke-Az -Args @('cognitiveservices','account','keys','list','-g',$ResourceGroup,'-n',$FoundryName,'--query','key1','-o','tsv')) -join ''
$foundryLast4 = if ($foundryKey.Length -ge 4) { $foundryKey.Substring($foundryKey.Length - 4) } else { 'n/a' }
$projectEndpoint = ($foundryEp.TrimEnd('/') -replace 'cognitiveservices\.azure\.com','services.ai.azure.com') + "/api/projects/$ProjectName"

# ----------------------------------------------------------------------------
# Smoke test: plain chat call against the gpt-4o deployment
# ----------------------------------------------------------------------------

Write-Section 'Smoke test: chat completion against gpt-4o deployment'

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
    SubscriptionId      = $acct.id
    TenantId            = $acct.tenantId
    ResourceGroup       = $ResourceGroup
    Region              = $Location
    FoundryResource     = $FoundryName
    FoundryProject      = $ProjectName
    FoundryEndpoint     = $foundryEp
    ProjectEndpoint     = $projectEndpoint
    ChatDeployment      = $ChatDeploymentName
    ChatModel           = "$ChatModelName ($ChatModelVersion, Standard, cap 10)"
    ManagedIdentityOid  = $identityOid
    FoundryKey1Last4    = $foundryLast4
    TeammateUpn         = "$TeammateUpn (NO role on the Foundry -- that is the RBAC demo)"
    PortalUrl           = "https://portal.azure.com/#@$($acct.tenantId)/resource/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/overview"
    IamPortalUrl        = "https://portal.azure.com/#@$($acct.tenantId)/resource/subscriptions/$($acct.id)/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryName/users"
    FoundryPortalUrl    = 'https://ai.azure.com/'
}

$result | Format-List

Write-Host ''
Write-Host 'Paste into .env (see .env.example in fabrikam-chat/ or demo/):' -ForegroundColor Cyan
Write-Host "  FOUNDRY_PROJECT_ENDPOINT=$projectEndpoint" -ForegroundColor Gray
Write-Host "  FOUNDRY_MODEL_NAME=$ChatDeploymentName" -ForegroundColor Gray
Write-Host ''
Write-Host 'Auth pattern: keyless (DefaultAzureCredential). No keys in .env for L10.' -ForegroundColor Cyan
Write-Host '  The credential chain picks up your az login token at runtime.' -ForegroundColor Gray
Write-Host ''
Write-Host 'RBAC demo prep:' -ForegroundColor Cyan
Write-Host "  Second terminal pane signed in as: $TeammateUpn" -ForegroundColor Gray
Write-Host '  That identity has NO role on the Foundry -> will hit 403 on the chat call.' -ForegroundColor Gray
Write-Host '  Live demo in the Azure portal IAM blade:' -ForegroundColor Gray
Write-Host "    $($result.IamPortalUrl)" -ForegroundColor Gray
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Open VS Code at the demo/fabrikam-chat/ folder. Confirm `az account show`.' -ForegroundColor Gray
Write-Host '  2. Build chat.py from scratch following the lesson flow.' -ForegroundColor Gray
Write-Host '  3. Build the loop, add streaming, run with three test prompts.' -ForegroundColor Gray
Write-Host '  4. RBAC demo: swap to the teammate terminal, demo the 403, assign the role' -ForegroundColor Gray
Write-Host '     in the IAM blade, rerun for success.' -ForegroundColor Gray
Write-Host "  5. When done: .\Deploy-Lesson10-Infrastructure.ps1 -Cleanup" -ForegroundColor 