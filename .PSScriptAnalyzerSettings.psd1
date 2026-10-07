@{
    Severity = @('Error', 'Warning')

    # Projectbewuste uitsluitingen (elk met reden):
    # - PSAvoidUsingWriteHost: WinPE-consolestijl; Write-Host is hier bewust de outputvector.
    # - PSUseApprovedVerbs: bestaande publieke werkwoordsvormen zijn ingeburgerd.
    # - PSUseShouldProcessForStateChangingFunctions: de WinPE-consoleflow gebruikt bewust
    #   geen -Confirm/-WhatIf; de enige bevestiging is de 15-secondenaftelling.
    # - PSAvoidUsingEmptyCatchBlock: bewuste terugvalpaden (console zonder cursorpositionering).
    # - PSUseSingularNouns: bestaande functienamen (bijv. Test-Prerequisites, Invoke-WinPEDriversPhase).
    # - PSReviewUnusedParameter / PSUseDeclaredVarsMoreThanAssignments: bekende false positives
    #   bij script-scope-variabelen die binnen functies worden gebruikt.
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
