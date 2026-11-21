using module ./Providence.Field.psm1
using module ./StudentTeacherObservation.psm1
using module ./StudentTextEvidence.psm1
using module ./StudentSourceInventory.psm1
#requires -Version 7.4
[CmdletBinding()]
param(
    [string] $BankPath = (Join-Path $PSScriptRoot '../data/source-bank'),
    [string] $ReplayArchive
)

$ErrorActionPreference = 'Stop'
$inventory = Open-StudentSourceInventory (Join-Path $BankPath 'sources.bin')
$documents = @{}
foreach ($file in Get-ChildItem (Join-Path $BankPath 'linguistic/pg*.bin') -File) {
    $document = Open-StudentTextEvidence $file.FullName $inventory
    $documents.Add($document.Source.Id,$document)
}
$executions = @(foreach ($index in Get-ChildItem (Join-Path $BankPath 'paired-teachers') -Filter stock-execution.bin -Recurse -File | Sort-Object FullName | Select-Object -First 2) {
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $index.DirectoryName 'observation.bin')))
    try {
        if ($reader.ReadString() -cne 'StudentTeacherObservation/1') { throw 'Unexpected observation schema.' }
        $document = $documents[$reader.ReadString()]
    } finally { $reader.Dispose() }
    (Open-StudentTeacherObservation $index.DirectoryName $document).StockExecution
})
$execution,$other = $executions
$scope = $execution.Normalizations | Where-Object TokenFrames | Select-Object -First 1
if (!$scope -or !$other) { throw 'Retained run requires decoder token accumulators and a competing execution.' }
$reason = 'Investigate whether captured normalization scope agrees with the execution token clock'
$family = $execution.Teacher.Document.Source.EvidenceGroup
if ($ReplayArchive) {
    $restored = Import-ProvidenceField -Path $ReplayArchive
    $result = Read-StudentStockScopeRecord -Line ([IO.File]::ReadAllText("$ReplayArchive.nl1")) -Execution $execution
    $foreignRejected = $false
    try { $null = Read-StudentStockScopeRecord -Line ([IO.File]::ReadAllText("$ReplayArchive.nl1")) -Execution $other }
    catch { $foreignRejected = $_.Exception.Message -ceq 'Stock scope record refers to another execution.' }
    if (!$foreignRejected) { throw 'Scope record was not rejected against a different source execution.' }
    foreach ($referent in $execution,$result.Scope,$result.TokenClock,$result) {
        $null = $restored.Register($referent,'',$family)
    }
    foreach ($method in Get-StudentStockObservationMethod) { $restored.PublishObservation($method) }
    $reopened = $restored.Require($result.Scope,[StudentNormalizationClockBearing],$reason)
    if (![object]::ReferenceEquals($reopened.Resolution,$result) -or
        ![object]::ReferenceEquals($result.Scope,$scope) -or
        ![object]::ReferenceEquals($result.TokenClock.Execution,$execution) -or
        $restored.Investigations.Count -or $restored.ActualCalls) { throw 'Fresh reconstruction required rediscovery.' }
    [ordered]@{
        Site = $result.Scope.Site
        Status = $result.Status.ToString()
        Tokens = $result.CapturedFrames.Length
        ReloadDispatches = $restored.ActualCalls
        ForeignExecutionRejected = $foreignRejected
    } | ConvertTo-Json
    return
}
$field = New-ProvidenceField
$null = $field.Register($execution,'stock',$family)
$null = $field.Register($other,'other',$other.Teacher.Document.Source.EvidenceGroup)
$foreign = $other.ObserveTokenClock()
$null = $field.Register($foreign,'foreign-clock',$other.Teacher.Document.Source.EvidenceGroup)
$null = $field.Register($scope,'scope',$family)
$question = $field.Require($scope,[StudentNormalizationClockBearing],$reason)
if ($question.Status -cne 'Blocked') { throw 'The question must start blocked.' }
foreach ($method in Get-StudentStockObservationMethod) { $field.PublishObservation($method) }
$operation = @($field.Capabilities.Values | Where-Object InputType -EQ ([StudentStockNormalization]))
if ($operation.Count -ne 1) { throw 'Expected one applicable typed observation.' }
$item = $field.Investigations.Dequeue()
if ($item.CapabilityKey -cne $operation[0].Key) { throw 'Typed operation was not nominated by the requirement.' }
$field.Execute($item)
$result = $question.Resolution
if (!$result -or $result.Status -ne [StudentExecutionClockStatus]::Agreement -or
    ![object]::ReferenceEquals($result.Scope,$scope) -or
    ![object]::ReferenceEquals($result.TokenClock.Execution,$execution) -or
    [object]::ReferenceEquals($result.TokenClock,$foreign)) {
    throw 'Dispatch failed to produce a source-qualified scope investigation.'
}
$field.Withdraw($item.CapabilityKey)
if ($question.Status -cne 'Blocked') { throw 'Withdrawal left the result active.' }
$field.Restore($item.CapabilityKey)
if (![object]::ReferenceEquals($question.Resolution,$result)) { throw 'Restore replaced the observation.' }
$supplier = $operation[0].Dependencies[0]
$field.Withdraw($supplier)
if ($question.Status -cne 'Blocked') { throw 'Withdrawal of the clock supplier left the dependent judgment active.' }
$field.Restore($supplier)
if (![object]::ReferenceEquals($question.Resolution,$result)) { throw 'Supplier restoration replaced the observation.' }

$archive = Join-Path ([IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot '../build')).FullName) ('providence-dispatch-'+[guid]::NewGuid()+'.bin')
Save-ProvidenceField -Field $field -Path $archive
[IO.File]::WriteAllText("$archive.nl1",(Write-StudentStockScopeRecord -Observation $result -Reason $reason))
$restored = Import-ProvidenceField -Path $archive
foreach ($referent in $execution,$scope,$result.TokenClock,$result) {
    $null = $restored.Register($referent,$field.ObjectKey($referent),$family)
}
foreach ($method in Get-StudentStockObservationMethod) { $restored.PublishObservation($method) }
$reopened = $restored.Require($scope,[StudentNormalizationClockBearing],$reason)
if (![object]::ReferenceEquals($reopened.Resolution,$result) -or
    $restored.Investigations.Count -or $restored.ActualCalls) { throw 'Saved interpretation required rediscovery.' }

[ordered]@{
    Source = $execution.Teacher.Document.Source.Id
    Passage = $execution.Teacher.Start
    Site = $scope.Site
    Operation = $item.CapabilityKey
    ResultKey = $field.ObjectKey($result)
    Status = $result.Status.ToString()
    Tokens = $result.CapturedFrames.Length
    ScopeFrames = $scope.ScopeFrameCount()
    Dispatches = $field.ActualCalls
    ReloadDispatches = $restored.ActualCalls
    Archive = $archive
} | ConvertTo-Json
