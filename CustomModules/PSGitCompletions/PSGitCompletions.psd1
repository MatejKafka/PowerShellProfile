
@{
    RootModule        = 'PSGitCompletions.dll'
    ModuleVersion     = '2.37.0'
    GUID              = '456512b8-bb86-47d7-835b-486b21bf5381'
    Author            = 'PowerCode, MatejKafka'
    Copyright         = '(c) PowerCode, MatejKafka. All rights reserved.'
    Description       = 'Tab completions for git.exe'
    FunctionsToExport = ''
    CmdletsToExport   = ''
    VariablesToExport = ''
    AliasesToExport   = ''

    FileList = @("PSGitCompletions.psd1", "PSGitCompletions.dll")

    PrivateData = @{
        PSData = @{
            Tags = @('git')
            ProjectUri = 'http://github.com/MatejKafka/PSGitCompletions'
        }
    }
}

