#requires -Version 7.4
# Providence: incremental reflection-based structural perception over canonical CLR referents.
# This module does not claim acoustic, linguistic, or causal discoveries from a graph join.

using namespace System.Collections.Generic
using namespace System.Reflection

class ProvidenceBearing {
    [object] $Owner
    [object] $Referent
    [string] $OwnerKey
    [string] $ReferentKey
    [string] $CapabilityKey
    [string] $SourceFamily
    [DateTime] $ObservedAt
    [bool] $Valid = $true
}
class ProvidencePercept {
    [string] $Key
    [object] $Owner
    [object] $Referent
    [string] $OwnerKey
    [string] $ReferentKey
    [List[ProvidenceBearing]] $Bearings = [List[ProvidenceBearing]]::new()
    # Structural joins are observed evidence, not acquired linguistic percepts.
    [string] $Reliance = 'ObservedStructural'
    [bool] $Acquired = $false
    [long] $Version = 0
    [string] $Scope = 'Observed CLR reference identity in the current source graph'
    [void] Reconsider([Dictionary[string,ProvidenceCapability]] $capabilities) {
        $valid = 0
        foreach ($bearing in $this.Bearings) {
            $capability = $null
            if ($capabilities.TryGetValue($bearing.CapabilityKey,[ref]$capability) -and $capability.Valid) {
                $bearing.Valid = $true; $valid++
            } else { $bearing.Valid = $false }
        }
        $next = if ($valid -gt 0) { 'ObservedStructural' } else { 'Withdrawn' }
        if ($this.Reliance -cne $next) { $this.Reliance=$next; $this.Version++ }
    }
}
class ProvidenceDistinction {
    [string] $DeclaringType
    [string] $MemberName
    [int[]] $Partition
    [int] $DistinctValues
    [bool] $ReferenceIdentity
}
class ProvidenceReverieJudgment {
    [long] $Version
    [datetime] $ObservedAt
    [string] $Status
    [string[]] $CandidateKeys
    [string] $ResolutionCapability
    [ProvidenceDistinction[]] $Distinctions = @()
}
class ProvidenceReverie {
    [string] $Key
    [string] $OwnerKey
    [string] $MissingCapability
    [string] $Reason
    [string] $Status = 'Blocked'
    [type] $NeededType
    [object] $Owner
    [object] $Resolution
    [string] $ResolutionCapability
    [long] $Version = 0
    [ProvidencePercept[]] $Alternatives = @()
    [List[ProvidenceReverieJudgment]] $History = [List[ProvidenceReverieJudgment]]::new()

    hidden static [ProvidenceDistinction[]] CompareAlternatives([object[]] $alternatives,[string] $prefix,[int] $remainingDepth) {
        $surface = $alternatives[0].GetType()
        $distinctions = [List[ProvidenceDistinction]]::new()
        foreach ($member in $surface.GetProperties([BindingFlags]'Public,Instance')) {
            if (!$member.CanRead -or $member.GetIndexParameters().Length -or
                !$member.DeclaringType.Assembly.IsDynamic) { continue }
            # SMA class properties are observed CLR slots. Skip collection slots:
            # two separately allocated vectors need not encode different evidence.
            $type = $member.PropertyType
            if ($type -ne [string] -and [System.Collections.IEnumerable].IsAssignableFrom($type)) { continue }
            $partition = [int[]]::new($alternatives.Count)
            $references = $type -ne [string] -and !$type.IsValueType
            $reached = [object[]]::new($alternatives.Count)
            $values = if ($references) { [Dictionary[object,int]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance) }
                else { [Dictionary[object,int]]::new() }
            $complete = $true
            for ($i = 0; $i -lt $alternatives.Count; $i++) {
                $referent = $alternatives[$i]
                if (!$member.DeclaringType.IsInstanceOfType($referent)) {
                    $complete = $false
                    break
                }
                $value = $member.GetValue($referent)
                if ($null -eq $value -or ($references -and ($value -is [string] -or $value -is [ValueType] -or
                    $value -is [System.Collections.IEnumerable]))) {
                    $complete = $false
                    break
                }
                [int]$slot = 0
                if (!$values.TryGetValue($value,[ref]$slot)) {
                    $slot = $values.Count
                    $values.Add($value,$slot)
                }
                $partition[$i] = $slot
                $reached[$i] = $value
            }
            if ($complete) {
                $path = $prefix+$member.Name
                $distinctions.Add([ProvidenceDistinction]@{
                    DeclaringType = $member.DeclaringType.FullName
                    MemberName = $path
                    Partition = $partition
                    DistinctValues = $values.Count
                    ReferenceIdentity = $references
                })
                # Continue only where the competing observations actually lead
                # to different objects. A shared link cannot explain their split.
                if ($references -and $values.Count -gt 1 -and $remainingDepth -gt 1) {
                    $distinctions.AddRange([ProvidenceReverie]::CompareAlternatives($reached,$path+'.',$remainingDepth-1))
                }
            }
        }
        return $distinctions.ToArray()
    }

    [void] Reconsider([List[ProvidencePercept]] $relationships, [Dictionary[string,ProvidenceCapability]] $capabilities) {
        $candidates = [List[ProvidencePercept]]::new()
        $supported = [List[ProvidencePercept]]::new()
        $nextCapability = ''
        $unbound = $false
        foreach ($relationship in $relationships) {
            if ($relationship.Referent) {
                if (!$this.NeededType.IsInstanceOfType($relationship.Referent)) { continue }
                $candidates.Add($relationship)
            }
            foreach ($bearing in $relationship.Bearings) {
                $operation = $null
                if ($capabilities.TryGetValue($bearing.CapabilityKey,[ref]$operation) -and $operation.Valid) {
                    if (!$relationship.Referent) {
                        if ($this.NeededType.IsAssignableFrom($operation.OutputType) -or
                            $operation.OutputType.IsAssignableFrom($this.NeededType)) { $unbound = $true }
                        continue
                    }
                    $supported.Add($relationship)
                    if (!$nextCapability) { $nextCapability = $operation.Key }
                    break
                }
            }
        }
        $this.Alternatives = $candidates.ToArray()
        $nextStatus = 'Blocked'
        $nextResolution = $null
        if ($unbound) {
            $nextStatus = 'Unbound'
        } elseif ($supported.Count -eq 1) {
            $nextStatus = 'Resolved'
            $nextResolution = $supported[0].Referent
        } elseif ($supported.Count -gt 1) {
            $nextStatus = 'Ambiguous'
        }
        if (!$nextResolution) { $nextCapability = '' }
        $keys = [string[]]@($supported | ForEach-Object { $_.ReferentKey })
        if ($nextStatus -ceq $this.Status -and [object]::ReferenceEquals($nextResolution,$this.Resolution) -and
            $nextCapability -ceq $this.ResolutionCapability -and $this.History.Count -and
            [Linq.Enumerable]::SequenceEqual($keys,$this.History[-1].CandidateKeys)) { return }
        $this.Status = $nextStatus
        $this.Resolution = $nextResolution
        $this.ResolutionCapability = $nextCapability
        $this.Version++
        $judgment = [ProvidenceReverieJudgment]@{
            Version = $this.Version
            ObservedAt = [datetime]::UtcNow
            Status = $nextStatus
            CandidateKeys = $keys
            ResolutionCapability = $nextCapability
        }
        if ($nextStatus -ceq 'Ambiguous') {
            # As in collision-driven refinement, actual competing observations
            # expose which existing distinctions could matter. This is evidence
            # for another investigation, not a selection of the correct referent.
            foreach ($prior in $this.History) {
                if ($prior.Distinctions.Length -and [Linq.Enumerable]::SequenceEqual($keys,$prior.CandidateKeys)) {
                    $judgment.Distinctions = $prior.Distinctions
                    break
                }
            }
            if (!$judgment.Distinctions.Length) {
                $referents = [object[]]@($supported | ForEach-Object { $_.Referent })
                $judgment.Distinctions = [ProvidenceReverie]::CompareAlternatives($referents,'',2)
            }
        }
        $this.History.Add($judgment)
    }
}
class ProvidenceCapability {
    [string] $Key
    [type] $InputType
    [type] $OutputType
    [PropertyInfo[]] $Path = @()
    [MethodInfo] $Method
    [MethodInfo] $ArgumentMethod
    [string[]] $Dependencies = @()
    [string] $Kind = 'ReflectedMember'
    [bool] $Valid = $true
    [bool] $Suspended
    [bool] $ObservedOnRealReferent = $false
    [long] $Applications = 0
    [long] $Successful = 0
    [long] $Failures = 0
    [long] $ElapsedTicks = 0
    [int] $Depth = 1
}
class ProvidenceWork {
    [object] $Referent
    [string] $CapabilityKey
    [ProvidenceWork] static Create([object]$target,[string]$key) {
        $w=[ProvidenceWork]::new();$w.Referent=$target;$w.CapabilityKey=$key;return $w
    }
}
class ProvidenceField {
    [int] $MaxDepth = 3
    [int] $MaxCapabilities = 6000
    [long] $MaxReferents = 250000
    [Dictionary[string,ProvidenceCapability]] $Capabilities = [Dictionary[string,ProvidenceCapability]]::new([StringComparer]::Ordinal)
    [HashSet[MethodInfo]] $ObservationMethods = [HashSet[MethodInfo]]::new()
    [Dictionary[object,HashSet[string]]] $ObservationBindings = [Dictionary[object,HashSet[string]]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    [Dictionary[string,ProvidenceReverie]] $Reveries = [Dictionary[string,ProvidenceReverie]]::new([StringComparer]::Ordinal)
    [Dictionary[object,List[ProvidenceReverie]]] $RequirementsByOwner = [Dictionary[object,List[ProvidenceReverie]]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    [Dictionary[string,ProvidencePercept]] $Percepts = [Dictionary[string,ProvidencePercept]]::new([StringComparer]::Ordinal)
    [Dictionary[string,List[ProvidencePercept]]] $RelationshipsByOwner = [Dictionary[string,List[ProvidencePercept]]]::new([StringComparer]::Ordinal)
    [Dictionary[string,List[ProvidencePercept]]] $RelationshipsByReferent = [Dictionary[string,List[ProvidencePercept]]]::new([StringComparer]::Ordinal)
    [Dictionary[string,string]] $FileObservations = [Dictionary[string,string]]::new([StringComparer]::Ordinal)
    [Dictionary[object,string]] $ReferentKeys = [Dictionary[object,string]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    [Dictionary[object,string]] $Families = [Dictionary[object,string]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
    [Dictionary[string,object]] $ByKey = [Dictionary[string,object]]::new([StringComparer]::Ordinal)
    [Dictionary[string,List[ProvidencePercept]]] $PendingByKey = [Dictionary[string,List[ProvidencePercept]]]::new([StringComparer]::Ordinal)
    [Dictionary[string,List[string]]] $PendingWorkByKey = [Dictionary[string,List[string]]]::new([StringComparer]::Ordinal)
    [Dictionary[type,List[object]]] $ByType = [Dictionary[type,List[object]]]::new()
    [Queue[object]] $NewReferents = [Queue[object]]::new()
    [Queue[ProvidenceWork]] $Investigations = [Queue[ProvidenceWork]]::new()
    [HashSet[string]] $Scheduled = [HashSet[string]]::new([StringComparer]::Ordinal)
    [HashSet[string]] $ObservedPairs = [HashSet[string]]::new([StringComparer]::Ordinal)
    [HashSet[string]] $KnownCapabilities = [HashSet[string]]::new([StringComparer]::Ordinal)
    [long] $Observations = 0
    [long] $FilesCovered = 0
    [long] $BytesVerified = 0
    [long] $DistinctJoinPercepts = 0
    [long] $AcquiredCompositions = 0
    [long] $ActualCalls = 0
    [long] $Errors = 0
    [long] $RepeatedObservationsAvoided = 0
    [string] $State = 'Active'
    [bool] $PreferFocused = $false

    [string] ObjectKey([object]$o) {
        $key=''
        if ($this.ReferentKeys.TryGetValue($o,[ref]$key)) { return $key }
        throw 'Referent has not been registered'
    }
    [string] QualifiedKey([object]$o,[string]$suggested) {
        # Original source IDs and execution coordinates outrank incidental
        # traversal order. Borrowed CLR objects retain reference identity.
        switch ($o.GetType().Name) {
            'StudentSourceUnit' {
                if($o.Id){return 'source/'+[string]$o.Id}
            }
            'StudentSentenceEvidence' {
                if($o.Document -and $o.Document.Source){
                    return 'sentence/'+$o.Document.Source.Id+'/'+$o.Index
                }
            }
            'StudentTeacherObservation' {
                if($o.Document -and $o.Document.Source){
                    return 'teacher/'+$o.Document.Source.Id+'/'+$o.Start+'/'+$o.Length
                }
            }
            'StudentStockExecution' {
                if($o.Teacher -and $o.Teacher.Document){
                    return 'execution/'+$o.Teacher.Document.Source.Id+'/'+$o.Teacher.Start+'/'+
                        $o.Teacher.Length+'/'+$o.Recipe
                }
            }
            'StudentStockActivation' {
                if($o.Execution -and $o.Execution.Teacher -and $o.Execution.Teacher.Document){
                    return 'activation/'+$o.Execution.Teacher.Document.Source.Id+'/'+
                        $o.Execution.Teacher.Start+'/'+$o.Execution.Teacher.Length+'/'+
                        $o.Execution.Recipe+'/'+$o.Stage+'/'+$o.Axes+'/'+$o.Checksum
                }
            }
            'StudentStockNormalization' {
                if ($o.Execution -and $o.Execution.Teacher.Document.Source) {
                    return $this.QualifiedKey($o.Execution,$suggested)+'/normalization/'+$o.Site
                }
            }
            'StudentExecutionClockBearing' {
                if ($o.Execution -and $o.Execution.Teacher.Document.Source) {
                    return $this.QualifiedKey($o.Execution,$suggested)+'/token-clock'
                }
            }
            'StudentDecoderHandoff' {
                if ($o.Execution -and $o.Execution.Teacher.Document.Source) {
                    return $this.QualifiedKey($o.Execution,$suggested)+'/decoder-handoff'
                }
            }
            'StudentDecoderHandoffBearing' {
                if ($o.Handoff -and $o.Handoff.Execution.Teacher.Document.Source) {
                    return $this.QualifiedKey($o.Handoff,$suggested)+'/input-comparison'
                }
            }
            'StudentNormalizationClockBearing' {
                if ($o.Scope -and $o.Scope.Execution.Teacher.Document.Source) {
                    return $this.QualifiedKey($o.Scope,$suggested)+'/token-scope'
                }
            }
        }
        return $suggested
    }
    [bool] IsReferenceType([type]$t) {
        if ($null -eq $t -or $t.IsPrimitive -or $t.IsEnum -or $t.IsValueType -or $t -eq [string] -or $t -eq [object]) { return $false }
        if ($t -eq [byte[]] -or $t -eq [single[]] -or $t -eq [double[]] -or $t -eq [int[]] -or $t -eq [long[]]) { return $false }
        if ([Delegate].IsAssignableFrom($t) -or [IO.Stream].IsAssignableFrom($t)) { return $false }
        return $true
    }
    [type] ElementType([type]$t) {
        if ($t.IsArray) { return $t.GetElementType() }
        if ($t.IsGenericType) {
            foreach ($arg in $t.GetGenericArguments()) {
                if ($this.IsReferenceType($arg) -and $arg -ne [string]) { return $arg }
            }
        }
        return $t
    }
    [bool] ShouldInspect([type]$type) {
        if ($type.IsPrimitive -or $type.IsValueType -or $type -eq [string]) { return $false }
        # Limit automatic traversal to the Student's dynamically defined CLR types,
        # SMA ASTs, and actual source/semantic-bearing classes supplied by an adapter.
        if ($type.Assembly.IsDynamic) { return $true }
        if ([Management.Automation.Language.Ast].IsAssignableFrom($type)) { return $true }
        if ($type.FullName -and $type.FullName.StartsWith('System.Management.Automation.Language.',[StringComparison]::Ordinal)) { return $true }
        return $false
    }
    [bool] Register([object]$referent,[string]$key,[string]$family) {
        if ($null -eq $referent -or !$this.ShouldInspect($referent.GetType())) { return $false }
        if ($this.ReferentKeys.ContainsKey($referent)) {
            $this.RepeatedObservationsAvoided++
            return $false
        }
        $key=$this.QualifiedKey($referent,$key)
        if ($this.ReferentKeys.Count -ge $this.MaxReferents) { throw 'Configured canonical referent bound reached.' }
        if ($this.ByKey.ContainsKey($key) -and ![object]::ReferenceEquals($this.ByKey[$key],$referent)) {
            throw "Stable source key collision: $key"
        }
        $this.ReferentKeys.Add($referent,$key)
        $this.ByKey[$key]=$referent
        $claims=$null
        if($this.PendingByKey.TryGetValue($key,[ref]$claims)){
            foreach($claim in $claims){
                if($claim.OwnerKey -ceq $key){$claim.Owner=$referent}
                if($claim.ReferentKey -ceq $key){$claim.Referent=$referent}
                if($claim.Owner){$this.ReconsiderOwner($claim.Owner)}
            }
            $null=$this.PendingByKey.Remove($key)
        }
        $pendingJobs=$null
        if($this.PendingWorkByKey.TryGetValue($key,[ref]$pendingJobs)){
            foreach($capKey in $pendingJobs){$this.Schedule($referent,$capKey)}
            $null=$this.PendingWorkByKey.Remove($key)
        }
        $this.Families.Add($referent,$family)
        $type = $referent.GetType()
        if (!$this.ByType.ContainsKey($type)) { $this.ByType.Add($type,[List[object]]::new()) }
        $this.ByType[$type].Add($referent)
        $this.NewReferents.Enqueue($referent)
        foreach ($cap in $this.Capabilities.Values) {
            if ($cap.Valid -and $cap.InputType.IsAssignableFrom($type)) { $this.Schedule($referent,$cap.Key) }
        }
        return $true
    }
    [void] IndexRelationship([ProvidencePercept] $relationship) {
        $owner = $relationship.OwnerKey
        if (!$this.RelationshipsByOwner.ContainsKey($owner)) {
            $this.RelationshipsByOwner.Add($owner,[List[ProvidencePercept]]::new())
        }
        $this.RelationshipsByOwner[$owner].Add($relationship)
        $referent = $relationship.ReferentKey
        if (!$this.RelationshipsByReferent.ContainsKey($referent)) {
            $this.RelationshipsByReferent.Add($referent,[List[ProvidencePercept]]::new())
        }
        $this.RelationshipsByReferent[$referent].Add($relationship)
    }

    [ProvidencePercept[]] Alignments([object] $unit) {
        $key = $this.ObjectKey($unit)
        $links = [List[ProvidencePercept]]::new()
        $outgoing = $null
        if ($this.RelationshipsByOwner.TryGetValue($key,[ref]$outgoing)) {
            $links.AddRange($outgoing)
        }
        $incoming = $null
        if ($this.RelationshipsByReferent.TryGetValue($key,[ref]$incoming)) {
            foreach ($link in $incoming) {
                if ($link.OwnerKey -cne $key) { $links.Add($link) }
            }
        }
        return $links.ToArray()
    }

    [void] ReconsiderOwner([object] $owner) {
        $requirements = $null
        if (!$this.RequirementsByOwner.TryGetValue($owner,[ref]$requirements)) { return }
        $relationships = $null
        $null = $this.RelationshipsByOwner.TryGetValue($this.ObjectKey($owner),[ref]$relationships)
        foreach ($requirement in $requirements) { $requirement.Reconsider($relationships,$this.Capabilities) }
    }

    [ProvidencePercept[]] ObservationsBy([object] $owner,[string] $operation) {
        $relationships = $null
        if (!$this.RelationshipsByOwner.TryGetValue($this.ObjectKey($owner),[ref]$relationships)) { return @() }
        $results = [List[ProvidencePercept]]::new()
        foreach ($relationship in $relationships) {
            if (!$relationship.Referent) { continue }
            foreach ($bearing in $relationship.Bearings) {
                if ($bearing.CapabilityKey -ceq $operation) {
                    $results.Add($relationship)
                    break
                }
            }
        }
        return $results.ToArray()
    }

    [void] Schedule([object]$referent,[string]$key) {
        $cap=$null
        if (!$this.Capabilities.TryGetValue($key,[ref]$cap) -or !$cap.Valid) { return }
        if (!$cap.InputType.IsAssignableFrom($referent.GetType())) { return }
        if ($cap.Kind -ceq 'ObservationMethod') {
            $bindings = $null
            if (!$cap.Method -or !$this.ObservationBindings.TryGetValue($referent,[ref]$bindings) -or !$bindings.Contains($key)) { return }
            if ($this.ObservationsBy($referent,$key).Count) { return }
        }
        if ($cap.Method -or $cap.Kind -ceq 'ObservationMethod' -or $cap.Depth -gt 1) {
            $requirements=$null
            if (!$this.RequirementsByOwner.TryGetValue($referent,[ref]$requirements)) { return }
            $applicable=$false
            foreach($requirement in $requirements){
                if($requirement.NeededType -and
                    $requirement.NeededType.IsAssignableFrom($cap.OutputType)){
                    $applicable=$true
                    break
                }
            }
            if(!$applicable){return}
        }
        $token = [string][Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($referent)+'/'+$this.ObjectKey($referent)+'/'+$key
        if ($this.Scheduled.Add($token)) { $this.Investigations.Enqueue([ProvidenceWork]::Create($referent,$key)) }
    }
    [void] IntroduceCapability([ProvidenceCapability]$cap) {
        if ($this.Capabilities.ContainsKey($cap.Key) -or $this.Capabilities.Count -ge $this.MaxCapabilities) { return }
        $this.Capabilities.Add($cap.Key,$cap)
        foreach ($knownType in $this.ByType.Keys) {
            if ($cap.InputType.IsAssignableFrom($knownType)) {
                foreach ($obj in $this.ByType[$knownType]) { $this.Schedule($obj,$cap.Key) }
            }
        }
        # An available typed capability can wake a previously blocked question.
        foreach ($reverie in $this.Reveries.Values) {
            if (!$reverie.Owner -or !$reverie.NeededType) { continue }
            if ($cap.InputType.IsAssignableFrom($reverie.Owner.GetType()) -and
                $reverie.NeededType.IsAssignableFrom($cap.OutputType)) {
                $this.Schedule($reverie.Owner,$cap.Key)
            }
        }
        # Compose typed property paths only after both constituents exist as actual
        # observed CLR operations. No named clock, morphology, or model target.
        if ($cap.Method -or $cap.Depth -ge $this.MaxDepth) { return }
        $existing=[ProvidenceCapability[]]@($this.Capabilities.Values)
        foreach ($other in $existing) {
            if ($other.Key -ceq $cap.Key) { continue }
            if ($this.Capabilities.Count -ge $this.MaxCapabilities) { break }
            if ($cap.Depth + $other.Depth -gt $this.MaxDepth) { continue }
            if ($other.InputType.IsAssignableFrom($cap.OutputType)) { $this.TryCompose($cap,$other) }
            if ($cap.InputType.IsAssignableFrom($other.OutputType)) { $this.TryCompose($other,$cap) }
        }
    }
    [void] TryCompose([ProvidenceCapability]$first,[ProvidenceCapability]$second) {
        if ($first.Kind -ceq 'ObservationMethod' -or $second.Kind -ceq 'ObservationMethod') { return }
        if (!$first.ObservedOnRealReferent -or !$second.ObservedOnRealReferent -or !$first.Valid -or !$second.Valid) { return }
        if ($first.Depth + $second.Depth -gt $this.MaxDepth) { return }
        $path = [PropertyInfo[]]@($first.Path + $second.Path)
        if ($path.Count -gt $this.MaxDepth) { return }
        $key = 'PATH/'+$first.InputType.AssemblyQualifiedName+'/'+(($path | ForEach-Object { $_.DeclaringType.FullName + '.' + $_.Name }) -join '->')
        if ($this.Capabilities.ContainsKey($key) -or $this.Capabilities.Count -ge $this.MaxCapabilities) { return }
        $composed=[ProvidenceCapability]::new()
        $composed.Key=$key;$composed.InputType=$first.InputType;$composed.OutputType=$second.OutputType
        $composed.Path=$path;$composed.Depth=$path.Count;$composed.Kind='AcquiredComposition'
        $composed.Dependencies=[string[]]@($first.Key,$second.Key)
        $this.AcquiredCompositions++
        $this.IntroduceCapability($composed)
    }

    [void] PublishObservation([MethodInfo] $method) {
        if (!$method -or !$method.IsPublic -or $method.IsStatic -or $method.ContainsGenericParameters -or
            !$this.IsReferenceType($method.ReturnType) -or $method.GetParameters().Length -gt 1) {
            throw 'Expected a public, typed observation method with at most one argument.'
        }
        if (!$this.ObservationMethods.Add($method)) { return }
        foreach ($requirement in $this.Reveries.Values) {
            if ($requirement.Owner -and $requirement.NeededType) { $this.FindObservation($requirement) }
        }
    }

    [void] FindObservation([ProvidenceReverie] $requirement) {
        $receiverType = $requirement.Owner.GetType()
        foreach ($method in $this.ObservationMethods) {
            if (!$method.DeclaringType.IsAssignableFrom($receiverType) -or
                !$requirement.NeededType.IsAssignableFrom($method.ReturnType)) { continue }
            $parameters = $method.GetParameters()
            if (!$parameters.Length) {
                $this.BindObservation($requirement.Owner,$method,$null,$null)
                continue
            }
            # The argument is produced from an object reached directly from the
            # receiver. A clock on another execution is never an argument candidate.
            $routes = [List[ProvidenceCapability]]::new()
            foreach ($property in $receiverType.GetProperties([BindingFlags]'Public,Instance')) {
                if (!$property.CanRead -or $property.GetIndexParameters().Length) { continue }
                foreach ($factory in $this.ObservationMethods) {
                    if ($factory.GetParameters().Length -or !$factory.DeclaringType.IsAssignableFrom($property.PropertyType) -or
                        !$parameters[0].ParameterType.IsAssignableFrom($factory.ReturnType) -or !$property.GetValue($requirement.Owner)) { continue }
                    $route = [ProvidenceCapability]::new()
                    $route.Path = @($property)
                    $route.ArgumentMethod = $factory
                    $routes.Add($route)
                }
            }
            if ($routes.Count -eq 1) {
                $this.BindObservation($requirement.Owner,$method,$routes[0].Path[0],$routes[0].ArgumentMethod)
            }
        }
    }

    [string] ObservationKey([MethodInfo] $method,[PropertyInfo] $route,[MethodInfo] $factory) {
        $key = 'OBSERVE/'+$method.DeclaringType.FullName+'/'+$method.Name+'/'+$method.ReturnType.FullName
        if ($route) { $key += '/'+$method.GetParameters()[0].ParameterType.FullName+'/'+$route.Name+'/'+$factory.DeclaringType.FullName+'/'+$factory.Name }
        return $key
    }

    [void] BindObservation([object] $owner,[MethodInfo] $method,[PropertyInfo] $route,[MethodInfo] $factory) {
        $key = $this.ObservationKey($method,$route,$factory)
        $dependency = ''
        if ($route) {
            $argumentOwner = $route.GetValue($owner)
            if (!$argumentOwner) { return }
            $null = $this.Register($argumentOwner,$this.ObjectKey($owner)+'/argument-owner',$this.Families[$owner])
            $dependency = $this.ObservationKey($factory,$null,$null)
            $this.BindObservation($argumentOwner,$factory,$null,$null)
            if (!$this.Capabilities.ContainsKey($dependency)) { return }
        }
        $operation = $null
        if (!$this.Capabilities.TryGetValue($key,[ref]$operation)) {
            $operation = [ProvidenceCapability]::new()
            $operation.Key=$key
            $operation.InputType=$method.DeclaringType
            $operation.OutputType=$method.ReturnType
            $operation.Kind='ObservationMethod'
            $operation.Method=$method
            $operation.ArgumentMethod=$factory
            if ($route) {
                $operation.Path=@($route)
                $operation.Dependencies=@($dependency)
                $operation.Valid=$this.Capabilities[$dependency].Valid
            }
            $this.IntroduceCapability($operation)
            if (!$this.Capabilities.ContainsKey($key)) { return }
        } else {
            $operation.Method=$method
            $operation.ArgumentMethod=$factory
        }
        if (!$this.ObservationBindings.ContainsKey($owner)) {
            $this.ObservationBindings.Add($owner,[HashSet[string]]::new([StringComparer]::Ordinal))
        }
        $null = $this.ObservationBindings[$owner].Add($key)
        $this.Schedule($owner,$key)
    }
    [void] Inspect([object]$owner) {
        $type=$owner.GetType()
        foreach ($property in $type.GetProperties([BindingFlags]'Public,Instance')) {
            if ($property.GetIndexParameters().Length -gt 0 -or !$property.CanRead) { continue }
            $out=$this.ElementType($property.PropertyType)
            if ($out -eq [object]) {
                # PowerShell class adapters often declare object-valued borrowed references.
                # Read the actual value, preserving its runtime CLR type and identity.
                $observed=$property.GetValue($owner)
                if ($null -eq $observed) { continue }
                $out=$this.ElementType($observed.GetType())
            }
            if (!$this.IsReferenceType($out) -or !$this.ShouldInspect($out)) { continue }
            $key='PATH/'+$type.AssemblyQualifiedName+'/'+$property.DeclaringType.FullName+'.'+$property.Name
            if (!$this.Capabilities.ContainsKey($key)) {
                $c=[ProvidenceCapability]::new();$c.Key=$key;$c.InputType=$type;$c.OutputType=$out;$c.Path=[PropertyInfo[]]@($property)
                $this.IntroduceCapability($c)
            }
        }
    }
    [object[]] ReadTargets([object]$owner,[PropertyInfo]$property) {
        $value=$property.GetValue($owner)
        if ($null -eq $value) { return @() }
        if ($value -is [System.Collections.IDictionary]) { return [object[]]@($value.Values) }
        if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            $items=[List[object]]::new()
            foreach ($element in $value) {
                if ($element -is [System.Collections.DictionaryEntry]) { $element=$element.Value }
                if ($null -ne $element) { $items.Add($element) }
            }
            return $items.ToArray()
        }
        return [object[]]@($value)
    }
    [void] Execute([ProvidenceWork]$work) {
        $cap=$null
        if (!$this.Capabilities.TryGetValue($work.CapabilityKey,[ref]$cap) -or !$cap.Valid) { return }
        if ($cap.Kind -ceq 'ObservationMethod' -and !$cap.Method) { return }
        if ($cap.Method -and $this.ObservationsBy($work.Referent,$cap.Key).Count) { return }
        $watch=[Diagnostics.Stopwatch]::StartNew()
        try {
            $nodes=[object[]]@($work.Referent)
            if ($cap.Method) {
                $arguments = [object[]]@()
                if ($cap.ArgumentMethod) {
                    $argumentOwner = $cap.Path[0].GetValue($work.Referent)
                    if (!$argumentOwner) { return }
                    $null = $this.Register($argumentOwner,$this.ObjectKey($work.Referent)+'/argument-owner',$this.Families[$work.Referent])
                    $supplier = $cap.Dependencies[0]
                    $supplied = $this.ObservationsBy($argumentOwner,$supplier)
                    if (!$supplied.Count) {
                        $this.Execute([ProvidenceWork]::Create($argumentOwner,$supplier))
                        $supplied = $this.ObservationsBy($argumentOwner,$supplier)
                    }
                    $parameter = $cap.Method.GetParameters()[0]
                    if ($supplied.Count -ne 1 -or !$parameter.ParameterType.IsInstanceOfType($supplied[0].Referent)) { return }
                    $arguments = [object[]]@($supplied[0].Referent)
                }
                $result = $cap.Method.Invoke($work.Referent,$arguments)
                $nodes = if ($result) { @($result) } else { @() }
            }
            foreach ($property in $(if (!$cap.Method) { $cap.Path })) {
                $next=[List[object]]::new()
                $seen=[HashSet[object]]::new([System.Collections.Generic.ReferenceEqualityComparer]::Instance)
                foreach ($node in $nodes) {
                    if ($null -eq $node -or !$property.DeclaringType.IsAssignableFrom($node.GetType())) { continue }
                    foreach ($item in $this.ReadTargets($node,$property)) {
                        if ($seen.Add($item) -and $this.ShouldInspect($item.GetType())) { $next.Add($item) }
                    }
                }
                $nodes=$next.ToArray()
                if (!$nodes.Count) { break }
            }
            $cap.Applications++
            $this.ActualCalls++
            if ($nodes.Count -eq 0) {
                # Null properties are often legitimate. Absence without an actual
                # investigative requirement is not an independently acquired reverie.
                return
            }
            $cap.Successful++
            if (!$cap.ObservedOnRealReferent) {
                $cap.ObservedOnRealReferent=$true
                $existing=[ProvidenceCapability[]]@($this.Capabilities.Values)
                foreach ($other in $existing) {
                    if ($other.ObservedOnRealReferent -and $other.Valid -and $other.Key -cne $cap.Key) {
                        if ($other.InputType.IsAssignableFrom($cap.OutputType)) { $this.TryCompose($cap,$other) }
                        if ($cap.InputType.IsAssignableFrom($other.OutputType)) { $this.TryCompose($other,$cap) }
                    }
                }
            }
            $ownerKey=$this.ObjectKey($work.Referent)
            $family=$this.Families[$work.Referent]
            $index=0
            foreach ($result in $nodes) {
                $id=$ownerKey+'/'+$cap.Key+'['+$index+']'
                if ($cap.Method) {
                    $resultKey = $this.QualifiedKey($result,$id)
                    if ($this.ByKey.ContainsKey($resultKey)) { $result = $this.ByKey[$resultKey] }
                }
                $null=$this.Register($result,$id,$family)
                $targetKey=$this.ObjectKey($result)
                $relationKey=$ownerKey+' => '+$targetKey
                $edgeKey=$relationKey+'/'+$cap.Key
                if ($this.ObservedPairs.Add($edgeKey)) {
                    $p=$null
                    if (!$this.Percepts.TryGetValue($relationKey,[ref]$p)) {
                        $p=[ProvidencePercept]::new();$p.Key=$relationKey;$p.Owner=$work.Referent;$p.Referent=$result
                        $p.OwnerKey=$ownerKey;$p.ReferentKey=$targetKey
                        $this.Percepts.Add($relationKey,$p)
                        $this.IndexRelationship($p)
                    }
                    $prior=$null
                    foreach($candidate in $p.Bearings){
                        if($candidate.CapabilityKey -ceq $cap.Key -and $candidate.SourceFamily -ceq $family){
                            $prior=$candidate;break
                        }
                    }
                    if($prior){
                        # A persisted bearing is verified again against the real CLR graph.
                        $prior.Owner=$work.Referent;$prior.Referent=$result
                        $prior.Valid=$cap.Valid
                        $this.RepeatedObservationsAvoided++
                    } else {
                        $bearing=[ProvidenceBearing]::new();$bearing.Owner=$work.Referent;$bearing.Referent=$result
                        $bearing.OwnerKey=$ownerKey;$bearing.ReferentKey=$targetKey;$bearing.CapabilityKey=$cap.Key
                        $bearing.SourceFamily=$family;$bearing.ObservedAt=[DateTime]::UtcNow
                        $p.Bearings.Add($bearing)
                        if ($p.Bearings.Count -eq 2) { $this.DistinctJoinPercepts++ }
                        $this.Observations++
                    }
                    $p.Reconsider($this.Capabilities)
                }
                $index++
            }
            $this.ReconsiderOwner($work.Referent)
        } catch {
            $cap.Failures++;$this.Errors++
            $id=$this.ObjectKey($work.Referent)+'/'+$cap.Key
            if (!$this.Reveries.ContainsKey($id)) {
                $gap=[ProvidenceReverie]::new();$gap.Key=$id;$gap.OwnerKey=$this.ObjectKey($work.Referent)
                $gap.MissingCapability=$cap.Key;$gap.Reason=$_.Exception.GetType().FullName+': '+$_.Exception.Message
                $this.Reveries.Add($id,$gap)
            }
        } finally { $cap.ElapsedTicks += $watch.ElapsedTicks }
    }
    [bool] Step() {
        $focus=$this.PreferFocused
        $this.PreferFocused=!$this.PreferFocused
        if ($focus -and $this.Investigations.Count -gt 0) {
            $this.Execute($this.Investigations.Dequeue());return $true
        }
        if ($this.NewReferents.Count -gt 0) { $this.Inspect($this.NewReferents.Dequeue());return $true }
        if ($this.Investigations.Count -gt 0) { $this.Execute($this.Investigations.Dequeue());return $true }
        return $false
    }
    [int] Advance([int]$budget) {
        $done=0
        for($n=0;$n -lt $budget;$n++) { if (!$this.Step()) { break };$done++ }
        $this.State=if($done -eq 0){'Quiescent'}else{'Active'}
        return $done
    }
    [void] Withdraw([string]$key) {
        if (!$this.Capabilities.ContainsKey($key)) { throw 'Unknown acquired capability' }
        $this.Capabilities[$key].Suspended = $true
        $pending=[Queue[string]]::new();$pending.Enqueue($key)
        $visited=[HashSet[string]]::new([StringComparer]::Ordinal)
        while($pending.Count){
            $item=$pending.Dequeue()
            if(!$visited.Add($item)){continue}
            $this.Capabilities[$item].Valid=$false
            foreach($child in $this.Capabilities.Values){ if($item -cin $child.Dependencies){$pending.Enqueue($child.Key)} }
        }
        foreach($p in $this.Percepts.Values){$p.Reconsider($this.Capabilities)}
        foreach ($owner in $this.RequirementsByOwner.Keys) { $this.ReconsiderOwner($owner) }
    }
    [void] Restore([string]$key) {
        if (!$this.Capabilities.ContainsKey($key)) { throw 'Unknown acquired capability' }
        $this.Capabilities[$key].Suspended=$false
        $changed=$true
        while($changed){
            $changed=$false
            foreach($cap in $this.Capabilities.Values){
                if($cap.Valid -or $cap.Suspended){continue}
                $all=$true;foreach($dependency in $cap.Dependencies){if(!$this.Capabilities[$dependency].Valid){$all=$false;break}}
                if($all){$cap.Valid=$true;$changed=$true}
            }
        }
        foreach($p in $this.Percepts.Values){$p.Reconsider($this.Capabilities)}
        foreach ($owner in $this.RequirementsByOwner.Keys) { $this.ReconsiderOwner($owner) }
        foreach($type in $this.ByType.Keys){
            foreach($obj in $this.ByType[$type]){
                foreach($cap in $this.Capabilities.Values){if($cap.Valid -and $cap.InputType.IsAssignableFrom($type)){$this.Schedule($obj,$cap.Key)}}
            }
        }
    }
    [ProvidenceReverie] Require([object]$owner,[type]$neededType,[string]$reason) {
        if(!$this.ReferentKeys.ContainsKey($owner)){throw 'Requirement owner must be an observed canonical referent.'}
        if(!$this.IsReferenceType($neededType)){throw 'Requirement must identify a CLR referent type.'}
        $id=$this.ObjectKey($owner)+'/needs/'+$neededType.FullName+'/'+$reason
        $r=$null
        if(!$this.Reveries.TryGetValue($id,[ref]$r)){
            $r=[ProvidenceReverie]::new();$r.Key=$id;$r.OwnerKey=$this.ObjectKey($owner)
            $r.NeededType=$neededType;$r.Reason=$reason
            $this.Reveries.Add($id,$r)
        }
        if([object]::ReferenceEquals($r.Owner,$owner)){return $r}
        $r.Owner=$owner
        if(!$this.RequirementsByOwner.ContainsKey($owner)){
            $this.RequirementsByOwner.Add($owner,[List[ProvidenceReverie]]::new())
        }
        $this.RequirementsByOwner[$owner].Add($r)
        $this.ReconsiderOwner($owner)
        $this.FindObservation($r)
        foreach($c in $this.Capabilities.Values){
            if($c.Valid -and $c.InputType.IsAssignableFrom($owner.GetType()) -and
                $neededType.IsAssignableFrom($c.OutputType)){$this.Schedule($owner,$c.Key)}
        }
        return $r
    }
    [object] Status() {
        $withdrawn=0;foreach($p in $this.Percepts.Values){if($p.Reliance -ceq 'Withdrawn'){$withdrawn++}}
        $acquired=0;foreach($p in $this.Percepts.Values){if($p.Acquired){$acquired++}}
        return [pscustomobject]@{ State=$this.State; Referents=$this.ReferentKeys.Count; StructuralRelations=$this.Percepts.Count
            AcquiredPercepts=$acquired
            MultiplePathRelations=$this.DistinctJoinPercepts; Capabilities=$this.Capabilities.Count; AcquiredCompositions=$this.AcquiredCompositions
            Reveries=$this.Reveries.Count; Withdrawn=$withdrawn; Observations=$this.Observations; Calls=$this.ActualCalls
            PendingRoots=$this.NewReferents.Count; PendingInvestigations=$this.Investigations.Count; FilesCovered=$this.FilesCovered
            BytesVerified=$this.BytesVerified; RepeatedObservationsAvoided=$this.RepeatedObservationsAvoided; Errors=$this.Errors }
    }
}

function New-ProvidenceField { [CmdletBinding()]param() return [ProvidenceField]::new() }


# Resolve a source-defined PowerShell class by semantic CLR full name when its
# generated assembly name changes across processes. Never deserialize as text.
function Resolve-ProvidenceType {
    param([Parameter(Mandatory)][string]$Identity)
    $type=[type]::GetType($Identity,$false)
    if($type){return $type}
    $fullName=$Identity.Split(',')[0].Trim()
    foreach($assembly in [AppDomain]::CurrentDomain.GetAssemblies()){
        $candidate=$assembly.GetType($fullName,$false)
        if($candidate){return $candidate}
    }
    throw "CLR type unavailable in this process: $fullName; import its actual source module first"
}

function Save-ProvidenceField {
    [CmdletBinding()]param([Parameter(Mandatory)][ProvidenceField]$Field,[Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    $directory=[IO.Path]::GetDirectoryName($full);$null=[IO.Directory]::CreateDirectory($directory)
    $tmp=$full+'.'+[guid]::NewGuid().ToString('N')+'.partial'
    $writer=[IO.BinaryWriter]::new([IO.File]::Open($tmp,[IO.FileMode]::CreateNew))
    try {
        $writer.Write('Providence-StructuralField/5')
        $writer.Write($Field.FileObservations.Count)
        foreach($entry in $Field.FileObservations.GetEnumerator()){$writer.Write($entry.Key);$writer.Write($entry.Value)}
        $writer.Write($Field.Capabilities.Count)
        foreach($cap in $Field.Capabilities.Values){
            $writer.Write($cap.Key)
            $writer.Write($cap.InputType.FullName)
            $writer.Write($cap.OutputType.FullName)
            $writer.Write($cap.Path.Length)
            foreach($member in $cap.Path){$writer.Write($member.DeclaringType.FullName);$writer.Write($member.Name)}
            $writer.Write($cap.Valid);$writer.Write($cap.ObservedOnRealReferent);$writer.Write($cap.Suspended)
            $writer.Write($cap.Kind)
            $writer.Write($cap.Applications);$writer.Write($cap.Successful);$writer.Write($cap.Failures);$writer.Write($cap.ElapsedTicks)
            $writer.Write($cap.Dependencies.Length)
            foreach($depend in $cap.Dependencies){$writer.Write($depend)}
        }
        $writer.Write($Field.Percepts.Count)
        foreach($p in $Field.Percepts.Values){
            $writer.Write($p.OwnerKey);$writer.Write($p.ReferentKey);$writer.Write($p.Reliance)
            $writer.Write($p.Acquired);$writer.Write($p.Version);$writer.Write($p.Scope)
            $writer.Write($p.Bearings.Count)
            foreach($b in $p.Bearings){
                $writer.Write($b.CapabilityKey);$writer.Write($b.SourceFamily);$writer.Write($b.Valid)
                $writer.Write($b.ObservedAt.ToBinary())
            }
        }
        $writer.Write($Field.Reveries.Count)
        foreach($r in $Field.Reveries.Values){
            $writer.Write($r.Key);$writer.Write($r.OwnerKey);$writer.Write([string]$r.MissingCapability)
            $writer.Write($r.Reason);$writer.Write($r.Status);$writer.Write($r.Version)
            $writer.Write([string]$r.ResolutionCapability)
            $writer.Write($(if($r.NeededType){$r.NeededType.FullName}else{''}))
            $writer.Write($r.History.Count)
            foreach ($judgment in $r.History) {
                $writer.Write($judgment.Version);$writer.Write($judgment.ObservedAt.ToBinary())
                $writer.Write($judgment.Status);$writer.Write($judgment.ResolutionCapability)
                $writer.Write($judgment.CandidateKeys.Length)
                foreach ($key in $judgment.CandidateKeys) { $writer.Write($key) }
                $writer.Write($judgment.Distinctions.Length)
                foreach ($distinction in $judgment.Distinctions) {
                    $writer.Write($distinction.DeclaringType);$writer.Write($distinction.MemberName)
                    $writer.Write($distinction.DistinctValues);$writer.Write($distinction.ReferenceIdentity)
                    foreach ($slot in $distinction.Partition) { $writer.Write($slot) }
                }
            }
        }
        $pending=[List[object[]]]::new()
        foreach($job in $Field.Investigations){
            if($Field.ReferentKeys.ContainsKey($job.Referent)){
                $pending.Add([object[]]@($Field.ObjectKey($job.Referent),$job.CapabilityKey))
            }
        }
        foreach($kv in $Field.PendingWorkByKey.GetEnumerator()){
            foreach($capKey in $kv.Value){$pending.Add([object[]]@($kv.Key,$capKey))}
        }
        $writer.Write($pending.Count)
        foreach($entry in $pending){$writer.Write([string]$entry[0]);$writer.Write([string]$entry[1])}
        $writer.Flush();$writer.BaseStream.Flush($true)
    } finally {$writer.Dispose()}
    [IO.File]::Move($tmp,$full,$true)
}

function Import-ProvidenceField {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[switch]$CapabilitiesOnly)
    $field=[ProvidenceField]::new()
    $reader=[IO.BinaryReader]::new([IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path))
    try {
        $schema = $reader.ReadString()
        if($schema -cnotin 'Providence-StructuralField/2','Providence-StructuralField/3','Providence-StructuralField/4','Providence-StructuralField/5'){
            throw 'Unsupported field version; do not silently flatten or discard prior evidence'
        }
        $files=$reader.ReadInt32()
        for($i=0;$i -lt $files;$i++){$key=$reader.ReadString();$field.FileObservations[$key]=$reader.ReadString()}
        $count=$reader.ReadInt32()
        for($i=0;$i -lt $count;$i++){
            $c=[ProvidenceCapability]::new();$c.Key=$reader.ReadString()
            $c.InputType=Resolve-ProvidenceType $reader.ReadString()
            $c.OutputType=Resolve-ProvidenceType $reader.ReadString()
            $n=$reader.ReadInt32();$members=[List[PropertyInfo]]::new()
            for($j=0;$j -lt $n;$j++){
                $decl=Resolve-ProvidenceType $reader.ReadString();$memberName=$reader.ReadString()
                $member=$decl.GetProperty($memberName,[BindingFlags]'Public,Instance')
                if(!$member){throw "Missing method contract $($decl.FullName).$memberName"}
                $members.Add($member)
            }
            $c.Path=$members.ToArray();$c.Depth=$c.Path.Count
            $c.Valid=$reader.ReadBoolean();$c.ObservedOnRealReferent=$reader.ReadBoolean()
            if ($schema -cne 'Providence-StructuralField/2') { $c.Suspended=$reader.ReadBoolean() }
            else { $c.Suspended = !$c.Valid }
            if ($schema -cin 'Providence-StructuralField/4','Providence-StructuralField/5') { $c.Kind=$reader.ReadString() }
            $c.Applications=$reader.ReadInt64();$c.Successful=$reader.ReadInt64()
            $c.Failures=$reader.ReadInt64();$c.ElapsedTicks=$reader.ReadInt64()
            $deps=$reader.ReadInt32();$c.Dependencies=[string[]]@(for($j=0;$j -lt $deps;$j++){$reader.ReadString()})
            $field.Capabilities.Add($c.Key,$c)
            if($c.Depth -gt 1){$c.Kind='AcquiredComposition';$field.AcquiredCompositions++}
        }
        if($CapabilitiesOnly){
            # Keep the original archive intact. Rebind and reobserve live CLR evidence.
            foreach($cap in $field.Capabilities.Values){$cap.ObservedOnRealReferent=$false}
            return $field
        }
        $claims=$reader.ReadInt32()
        for($i=0;$i -lt $claims;$i++){
            $p=[ProvidencePercept]::new()
            $p.OwnerKey=$reader.ReadString();$p.ReferentKey=$reader.ReadString()
            $p.Key=$p.OwnerKey+' => '+$p.ReferentKey
            $p.Reliance=$reader.ReadString();$p.Acquired=$reader.ReadBoolean()
            $p.Version=$reader.ReadInt64();$p.Scope=$reader.ReadString()
            $evidence=$reader.ReadInt32()
            for($j=0;$j -lt $evidence;$j++){
                $b=[ProvidenceBearing]::new();$b.OwnerKey=$p.OwnerKey;$b.ReferentKey=$p.ReferentKey
                $b.CapabilityKey=$reader.ReadString();$b.SourceFamily=$reader.ReadString();$b.Valid=$reader.ReadBoolean()
                if ($schema -cne 'Providence-StructuralField/2') { $b.ObservedAt=[datetime]::FromBinary($reader.ReadInt64()) }
                $p.Bearings.Add($b)
            }
            $field.Percepts[$p.Key]=$p
            $field.IndexRelationship($p)
            foreach($key in @($p.OwnerKey,$p.ReferentKey)){
                if(!$field.PendingByKey.ContainsKey($key)){$field.PendingByKey[$key]=[List[ProvidencePercept]]::new()}
                $field.PendingByKey[$key].Add($p)
            }
        }
        $gaps=$reader.ReadInt32()
        for($i=0;$i -lt $gaps;$i++){
            $r=[ProvidenceReverie]::new()
            $r.Key=$reader.ReadString();$r.OwnerKey=$reader.ReadString();$r.MissingCapability=$reader.ReadString()
            $r.Reason=$reader.ReadString();$r.Status=$reader.ReadString();$r.Version=$reader.ReadInt64()
            $r.ResolutionCapability=$reader.ReadString()
            $typeName=$reader.ReadString()
            if($typeName){$r.NeededType=Resolve-ProvidenceType $typeName}
            if ($schema -cne 'Providence-StructuralField/2') {
                $count = $reader.ReadInt32()
                for ($j=0;$j -lt $count;$j++) {
                    $judgment = [ProvidenceReverieJudgment]::new()
                    $judgment.Version=$reader.ReadInt64()
                    $judgment.ObservedAt=[datetime]::FromBinary($reader.ReadInt64())
                    $judgment.Status=$reader.ReadString()
                    $judgment.ResolutionCapability=$reader.ReadString()
                    $length=$reader.ReadInt32()
                    $judgment.CandidateKeys=[string[]]@(for ($k=0;$k -lt $length;$k++) { $reader.ReadString() })
                    if ($schema -ceq 'Providence-StructuralField/5') {
                        $numberOfDistinctions = $reader.ReadInt32()
                        $judgment.Distinctions = [ProvidenceDistinction[]]@(for ($k=0;$k -lt $numberOfDistinctions;$k++) {
                            $distinction = [ProvidenceDistinction]::new()
                            $distinction.DeclaringType = $reader.ReadString()
                            $distinction.MemberName = $reader.ReadString()
                            $distinction.DistinctValues = $reader.ReadInt32()
                            $distinction.ReferenceIdentity = $reader.ReadBoolean()
                            $distinction.Partition = [int[]]@(for ($slot=0;$slot -lt $length;$slot++) { $reader.ReadInt32() })
                            $distinction
                        })
                    }
                    $r.History.Add($judgment)
                }
            }
            $field.Reveries[$r.Key]=$r
        }
        $jobs=$reader.ReadInt32()
        for($i=0;$i -lt $jobs;$i++){
            $key=$reader.ReadString();$capKey=$reader.ReadString()
            if(!$field.PendingWorkByKey.ContainsKey($key)){$field.PendingWorkByKey[$key]=[List[string]]::new()}
            $field.PendingWorkByKey[$key].Add($capKey)
        }
        # Canonical CLR objects are never reconstructed from display names. Actual
        # source scans must rebind them; pending work resumes when their owners appear.
        return $field
    } finally {$reader.Dispose()}
}

Export-ModuleMember -Function New-ProvidenceField,Save-ProvidenceField,Import-ProvidenceField
