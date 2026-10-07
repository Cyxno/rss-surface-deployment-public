@{
    Severity = @('Error', 'Warning')

    # Project-aware exclusions (each with a reason):
    # - PSAvoidUsingWriteHost: WinPE console style; Write-Host is deliberately the output vector here.
    # - PSUseApprovedVerbs: the existing public verb forms are established.
    # - PSUseShouldProcessForStateChangingFunctions: the WinPE console flow deliberately
    #   does not use -Confirm/-WhatIf; the only confirmation is the 15-second countdown.
    # - PSAvoidUsingEmptyCatchBlock: deliberate fallback paths (console without cursor positioning).
    # - PSUseSingularNouns: existing function names (e.g. Test-Prerequisites, Invoke-WinPEDriversPhase).
    # - PSReviewUnusedParameter / PSUseDeclaredVarsMoreThanAssignments: known false positives
    #   with script-scope variables that are used inside functions.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseApprovedVerbs',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseSingularNouns',
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments'
    )
    Rules        = @{
        PSAvoidDefaultValueSwitchParameter = @{ Enable = $true }
    }
}
