# PSScriptAnalyzer settings for this project:
#   Invoke-ScriptAnalyzer -Path Scripts -Recurse -Settings Scripts\PSScriptAnalyzerSettings.psd1
# Rules excluded on purpose:
#   AvoidUsingWriteHost            - this is an interactive console tool; colour output is the UI.
#   UseDeclaredVarsMoreThanAssignments - constants and data are set in one file and used in the
#                                    Lib files it loads, which the rule cannot see.
#   AvoidUsingEmptyCatchBlock      - best-effort steps (console tweaks, removing values that may
#                                    not exist) that must never stop a run.
#   AvoidUsingPositionalParameters - house style for the catalog and output helpers.
#   UseSingularNouns, UseShouldProcessForStateChangingFunctions - internal functions, not cmdlets.
@{
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidUsingEmptyCatchBlock'
        'PSAvoidUsingPositionalParameters'
        'PSUseSingularNouns'
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
