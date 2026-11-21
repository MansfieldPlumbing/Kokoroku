using module ./Providence.Field.psm1
using module ./Providence.Speech.psm1
using namespace System.Management.Automation.Language
[CmdletBinding()]
param(
    [string] $BankPath = (Join-Path $PSScriptRoot '../data/source-bank'),
    [string] $PscPath
)
$ErrorActionPreference='Stop'

$root = Join-Path $PSScriptRoot '..'
$base = [IO.Directory]::CreateDirectory((Join-Path $root "build/providence-review-$([guid]::NewGuid().ToString('N'))")).FullName
$reference=Join-Path $root 'phonemizer/Invoke-EnglishPhonemizer.ps1'
$zira=New-Module -Name ProvidenceZira -ArgumentList $reference -ScriptBlock {
    param($Reference)
    . $Reference -Import
}
$speech=& (Join-Path $PSScriptRoot 'Open-StudentSpeechInvestigation.ps1') -BankPath $BankPath -SourceIdentity Gutenberg/11 -ZiraModule $zira
$open=[Diagnostics.Stopwatch]::StartNew()
foreach($comparison in $speech.Comparisons){
    $view=Join-ProvidencePassage -Comparison $comparison
    $owner=$null
    foreach($occ in $view.Occurrences){
        if($occ.ZiraBearings.Length -and $occ.HumanCandidates.Length -gt 1){
            $owner=$occ.ZiraBearings[0];break
        }
    }
    if($owner){break}
}
if(!$owner){throw 'No retained competing candidate found'}
$field=New-ProvidenceField
$id="passage/$($view.Source.Id)/$($view.SourceStartUtf16)/zira/$($owner.Occurrence.TokenIndex)/$($owner.WordEvent.Event)"
$null=$field.Register($owner,$id,$view.Source.EvidenceGroup)
$need=$field.Require($owner,[ProvidenceHumanIntervalCandidate],'Find source-occurrence human bracket; exact timing remains unproved')
$null=$field.Advance(1500)
if($need.Status -ne 'Ambiguous'){throw "Expected actual competing human anchors, got $($need.Status); $($field.Errors) errors"}
$alts=$need.Alternatives
$before=@($alts | ForEach-Object { $_.Referent })
$discovered = $need.History[-1].Distinctions
$identities = @($discovered | Where-Object ReferenceIdentity)
$recording = $identities | Where-Object MemberName -CEQ Recording
$anchors = $identities | Where-Object MemberName -CEQ Anchor
if ($recording.DistinctValues -ne 1 -or $anchors.DistinctValues -ne $before.Count) {
    throw 'Autonomous comparison did not distinguish recognizer anchors from their shared recording.'
}
$utterances = $identities | Where-Object MemberName -CEQ Anchor.Utterance
$recognizedWord = $discovered | Where-Object MemberName -CEQ Anchor.RecognizedWord
if ($utterances.DistinctValues -ne $before.Count -or $recognizedWord.DistinctValues -ne 1 -or
    $discovered.MemberName.StartsWith('Recording.',$false,[Globalization.CultureInfo]::InvariantCulture) -contains $true) {
    throw 'The investigation did not follow the differing anchor roles and prune the shared recording.'
}
$links=$field.Alignments($owner)
$checks=0
$scanVisits=0
foreach($candidate in $alts){
    if($field.Alignments($candidate.Referent) -cnotcontains $candidate){throw 'Missing reverse link'}
    $scan=@(foreach ($relationship in $field.Percepts.Values) {
        $scanVisits++
        if ($relationship.OwnerKey -ceq $candidate.ReferentKey -or $relationship.ReferentKey -ceq $candidate.ReferentKey) {
            $relationship
        }
    })
    $indexed=$field.Alignments($candidate.Referent)
    if ($scan.Length -ne $indexed.Length -or @($scan | Where-Object { $indexed -cnotcontains $_ }).Count) {
        throw 'Alignment lookup and exhaustive recall differ'
    }
    $checks++
}
$operations=@($alts.Bearings.CapabilityKey | Sort-Object -Unique)
foreach($op in $operations){$field.Withdraw($op)}
if($need.Status -ne 'Blocked'){throw 'Withdrawal retained unsupported judgment'}
foreach($op in $operations){$field.Restore($op)}
if($need.Status -ne 'Ambiguous'){throw 'Readmission did not restore alternatives'}
if (![object]::ReferenceEquals($discovered,$need.History[-1].Distinctions)) {
    throw 'Readmission rediscovered the same distinctions.'
}
foreach($i in 0..($before.Count-1)){
    if(![object]::ReferenceEquals($before[$i],$need.Alternatives[$i].Referent)){throw 'Canonical identity changed'}
}
$path=Join-Path $base 'reconsideration.bin'
Save-ProvidenceField -Field $field -Path $path
$copy=Import-ProvidenceField -Path $path
if($copy.Reveries[$need.Key].History.Count -ne $need.History.Count){throw 'Journal did not round trip'}
$saved = $copy.Reveries[$need.Key].History[-1].Distinctions
if ($saved.Length -ne $discovered.Length) { throw 'Distinction history did not round trip.' }
for ($i = 0; $i -lt $saved.Length; $i++) {
    if ($saved[$i].MemberName -cne $discovered[$i].MemberName -or
        ![Linq.Enumerable]::SequenceEqual($saved[$i].Partition,$discovered[$i].Partition)) {
        throw 'A saved distinction changed.'
    }
}
$null=$copy.Register($owner,$id,$view.Source.EvidenceGroup)
$restored=$copy.Require($owner,[ProvidenceHumanIntervalCandidate],$need.Reason)
if($restored.Status -ne 'Unbound'){throw 'Archived alternatives treated as live'}
for($i=0;$i -lt $before.Count;$i++){
    $null=$copy.Register($before[$i],$alts[$i].ReferentKey,$view.Source.EvidenceGroup)
    if($i -lt $before.Count-1 -and $restored.Status -ne 'Unbound'){throw 'Partial reconstruction promoted an alternative'}
}
if($restored.Status -ne 'Ambiguous'){throw 'Rebinding failed to reconstruct the live judgment'}
$managedPath = $null
if ($PscPath) {
    Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
    $parseErrors = $null
    $source = [Parser]::ParseFile((Join-Path $PSScriptRoot 'Providence.Field.psm1'),[ref]$null,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
    $definitions = @($source.EndBlock.Statements | Where-Object {
        $_ -is [TypeDefinitionAst] -and $_.Name -cin 'ProvidenceDistinction','ProvidenceReverieJudgment'
    })
    $body = [StatementBlockAst]::new($definitions[0].Extent,[StatementAst[]]@($definitions | ForEach-Object Copy),$null)
    $ast = [ScriptBlockAst]::new($definitions[0].Extent,$null,$body,$false)
    $managedPath = Join-Path $base 'ProvidenceReverieJudgment.dll'
    $null = & (Resolve-Path -LiteralPath $PscPath).Path -Mode Compile -SourceAst $ast -ClassName ProvidenceReverieJudgment -ClassNames $definitions.Name -OutputPath $managedPath
    $assembly = [Reflection.Assembly]::LoadFrom($managedPath)
    $decodedType = $assembly.GetTypes() | Where-Object Name -CEQ ProvidenceReverieJudgment
    $distinctionType = $assembly.GetTypes() | Where-Object Name -CEQ ProvidenceDistinction
    $decoded = [Activator]::CreateInstance($decodedType)
    $record = $restored.History[-1]
    foreach ($property in $record.GetType().GetProperties()) {
        $fieldDefinition = $decodedType.GetField($property.Name)
        $value = $property.GetValue($record)
        if ($property.Name -ceq 'Distinctions') {
            $value = [Array]::CreateInstance($distinctionType,$record.Distinctions.Length)
            for ($i = 0; $i -lt $value.Length; $i++) {
                $emitted = [Activator]::CreateInstance($distinctionType)
                foreach ($slot in $record.Distinctions[$i].GetType().GetProperties()) {
                    $member = $distinctionType.GetField($slot.Name)
                    if ($member.FieldType -ne $slot.PropertyType) { throw 'Emitted distinction field type drifted' }
                    $member.SetValue($emitted,$slot.GetValue($record.Distinctions[$i]))
                }
                $value.SetValue($emitted,$i)
            }
        } elseif ($fieldDefinition.FieldType -ne $property.PropertyType) { throw 'Emitted judgment field type drifted' }
        $fieldDefinition.SetValue($decoded,$value)
        if (![object]::Equals($fieldDefinition.GetValue($decoded),$value)) { throw 'Emitted judgment lost its value' }
    }
}
[ordered]@{
    Source=$view.Source.Id; Passage=$view.SourceStartUtf16; Token=$owner.Occurrence.TokenIndex
    Word=$owner.Occurrence.OriginalSpelling; Alternatives=$before.Count; IncidentAlignments=$links.Length
    CandidateSources=@($before | ForEach-Object { @{Status=$_.Status;First100ns=$_.First100ns;End100ns=$_.End100ns} })
    DiscoveredDistinctions=$discovered
    ReverseLinks=$checks; ScanVisits=$scanVisits; History=$need.History; Work=$field.ActualCalls; Errors=$field.Errors; ElapsedMs=$open.ElapsedMilliseconds
    JudgmentAssembly=$need.History[0].GetType().Assembly.FullName
    EmittedJudgment=$managedPath
    Archive=$path
} | ConvertTo-Json -Depth 8
