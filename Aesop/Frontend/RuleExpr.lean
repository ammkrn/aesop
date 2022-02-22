/-
Copyright (c) 2022 Jannis Limperg. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Jannis Limperg
-/

import Aesop.Frontend.ParseT
import Aesop.Percent
import Aesop.Rule.Name
import Aesop.RuleBuilder
import Aesop.RuleSet

open Lean
open Lean.Meta

namespace Aesop.Frontend

variable [Monad m] [MonadError m]

namespace Parser

declare_syntax_cat Aesop.priority

syntax num "%" : Aesop.priority
syntax "-"? num : Aesop.priority

end Parser

inductive Priority
  | int (i : Int)
  | percent (p : Percent)
  deriving Inhabited

namespace Priority

def parse (stx : Syntax) : ParseT m Priority :=
  withRef stx do
    unless (← read).parsePriorities do throwError
      "aesop: unexpected priority."
    match stx with
    | `(priority| $p:numLit %) =>
      let p := p.toNat
      match Percent.ofNat p with
      | some p => return percent p
      | none => throwError "aesop: percentage '{p}%' is not between 0 and 100."
    | `(priority| - $i:numLit) =>
      return int $ - i.toNat
    | `(priority| $i:numLit) =>
      return int i.toNat
    | _ => unreachable!

instance : ToString Priority where
  toString
    | int i => toString i
    | percent p => p.toHumanString

def toInt? : Priority → Option Int
  | int i => some i
  | _ => none

def toPercent? : Priority → Option Percent
  | percent p => some p
  | _ => none

end Priority


namespace Parser

declare_syntax_cat Aesop.phase (behavior := symbol)

syntax &"safe" : Aesop.phase
syntax &"norm" : Aesop.phase
syntax &"unsafe" : Aesop.phase

end Parser

def parsePhaseName : Syntax → RuleName.Phase
  | `(phase| safe) => RuleName.Phase.safe
  | `(phase| norm) => RuleName.Phase.norm
  | `(phase| unsafe) => RuleName.Phase.unsafe
  | _ => unreachable!


namespace Parser

declare_syntax_cat Aesop.bool_lit (behavior := symbol)

syntax &"true" : Aesop.bool_lit
syntax &"false" : Aesop.bool_lit

end Parser

def parseBoolLit : Syntax → Bool
  | `(bool_lit| true) => true
  | `(bool_lit| false) => false
  | _ => unreachable!


namespace Parser

declare_syntax_cat Aesop.builder_option

syntax "(" &"uses_branch_state" ":=" Aesop.bool_lit ")" : Aesop.builder_option
syntax "(" &"immediate" ":=" "[" ident,+,? "]" ")" : Aesop.builder_option

syntax builderOptions := Aesop.builder_option*

end Parser

structure BuilderOptions (m : Type _ → Type _) (α : Type _) where
  parseOption : Syntax → m α -- parse a single `Aesop.builder_option`
  empty : α
  combine : α → α → α

namespace BuilderOptions

def parse [Inhabited α] (bo : BuilderOptions m α) : Syntax → m α
  | `(Parser.builderOptions| $opts:Aesop.builder_option*) =>
    opts.foldlM (init := bo.empty) λ o stx =>
      return bo.combine o (← bo.parseOption stx)
  | _ => unreachable!

protected def none (builder : RuleName.Builder) : BuilderOptions m Unit where
  parseOption _ :=
    throwError "aesop: builder {builder} does not accept any options"
  empty := ()
  combine := λ _ _ => ()

def tactic : BuilderOptions m TacticBuilderOptions where
  parseOption
    | `(builder_option| (uses_branch_state := $b:Aesop.bool_lit)) =>
      return { usesBranchState := parseBoolLit b }
    | _ => throwError "aesop: invalid option for builder {RuleName.Builder.tactic}"
  empty := { usesBranchState := true }
  combine o p := { usesBranchState := p.usesBranchState }

def forward : BuilderOptions m ForwardBuilderOptions where
  parseOption
    | `(builder_option| (immediate := [$ns:ident,*])) =>
      return { immediateHyps := (ns : Array Syntax).map (·.getId) }
    | _ => throwError "aesop: invalid option for builder {RuleName.Builder.forward}"
  empty := { immediateHyps := #[] }
  combine o p := { immediateHyps := p.immediateHyps }

end BuilderOptions


namespace Parser

declare_syntax_cat Aesop.builder_name (behavior := symbol)

syntax &"apply" : Aesop.builder_name
syntax &"simp" : Aesop.builder_name
syntax &"unfold" : Aesop.builder_name
syntax &"tactic" : Aesop.builder_name
syntax &"constructors" : Aesop.builder_name
syntax &"forward" : Aesop.builder_name
syntax &"cases" : Aesop.builder_name
syntax &"safe_default" : Aesop.builder_name
syntax &"unsafe_default" : Aesop.builder_name
syntax &"norm_default" : Aesop.builder_name

declare_syntax_cat Aesop.builder (behavior := symbol)

syntax Aesop.builder_name : Aesop.builder
syntax "(" Aesop.builder_name builderOptions ")" : Aesop.builder

end Parser

def parseBuilderName : Syntax → RuleName.Builder
  | `(builder_name| apply) => RuleName.Builder.apply
  | `(builder_name| simp) => RuleName.Builder.simp
  | `(builder_name| unfold) => RuleName.Builder.unfold
  | `(builder_name| tactic) => RuleName.Builder.tactic
  | `(builder_name| constructors) => RuleName.Builder.constructors
  | `(builder_name| forward) => RuleName.Builder.forward
  | `(builder_name| cases) => RuleName.Builder.cases
  | `(builder_name| safe_default) => RuleName.Builder.safeDefault
  | `(builder_name| unsafe_default) => RuleName.Builder.unsafeDefault
  | `(builder_name| norm_default) => RuleName.Builder.normDefault
  | _ => unreachable!

inductive Builder
  | apply
  | simp
  | unfold
  | tactic (opts : TacticBuilderOptions)
  | constructors
  | forward (opts : ForwardBuilderOptions)
  | cases
  | safeDefault
  | unsafeDefault
  | normDefault
  deriving Inhabited

namespace Builder

private def tacticBuilderOptionsToString (opts : TacticBuilderOptions) : String :=
  if opts.usesBranchState then "" else "(uses_branch_state := false)"

private def forwardBuilderOptionsToString (opts : ForwardBuilderOptions) : String :=
  if opts.immediateHyps.isEmpty then
    ""
  else
    s!"(immediate := {opts.immediateHyps})"

instance : ToString Builder where
  toString
    | apply => "(apply)"
    | simp => "(simp)"
    | unfold => "(unfold)"
    | tactic opts =>
      "(" ++ String.joinSep " " #["tactic", tacticBuilderOptionsToString opts] ++ ")"
    | constructors => "(constructors)"
    | forward opts =>
      "(" ++ String.joinSep " " #["forward", forwardBuilderOptionsToString opts] ++ ")"
    | cases => "(cases)"
    | safeDefault => "(safe_default)"
    | unsafeDefault => "(unsafe_default)"
    | normDefault => "(norm_default)"

def parseOptions (b : RuleName.Builder) (opts : Syntax) : m Builder := do
  match b with
  | RuleName.Builder.apply => checkNoOptions; return apply
  | RuleName.Builder.simp => checkNoOptions; return simp
  | RuleName.Builder.unfold => checkNoOptions; return unfold
  | RuleName.Builder.tactic =>
    return tactic $ ← BuilderOptions.tactic.parse opts
  | RuleName.Builder.constructors => checkNoOptions; return constructors
  | RuleName.Builder.forward =>
    return forward $ ← BuilderOptions.forward.parse opts
  | RuleName.Builder.cases => checkNoOptions; return cases
  | RuleName.Builder.safeDefault => checkNoOptions; return safeDefault
  | RuleName.Builder.unsafeDefault => checkNoOptions; return unsafeDefault
  | RuleName.Builder.normDefault => checkNoOptions; return normDefault
  where
    checkNoOptions := BuilderOptions.none b |>.parse opts

def parse : Syntax → m Builder
  | `(builder| $b:Aesop.builder_name) =>
    parseOptions (parseBuilderName b) (mkNode ``Parser.builderOptions #[])
  | `(builder| ($b:Aesop.builder_name $opts:builderOptions)) =>
    parseOptions (parseBuilderName b) opts
  | _ => unreachable!

def toRegularRuleBuilder : Builder →
    Option (RuleBuilder RegularRuleBuilderResult)
  | apply => RuleBuilder.apply
  | simp => none
  | unfold => none
  | tactic opts => RuleBuilder.tactic opts
  | constructors => RuleBuilder.constructors
  | forward opts => RuleBuilder.forward opts
  | cases => RuleBuilder.cases
  | safeDefault => RuleBuilder.safeDefault
  | unsafeDefault => RuleBuilder.unsafeDefault
  | normDefault => none

def toNormRuleBuilder : Builder →
    RuleBuilder NormRuleBuilderResult
  | apply => RuleBuilder.apply.toNormRuleBuilder
  | simp => RuleBuilder.normSimpLemmas
  | unfold => RuleBuilder.normSimpUnfold
  | tactic opts => RuleBuilder.tactic opts |>.toNormRuleBuilder
  | constructors => RuleBuilder.constructors.toNormRuleBuilder
  | forward opts => RuleBuilder.forward opts |>.toNormRuleBuilder
  | cases => RuleBuilder.cases.toNormRuleBuilder
  | safeDefault => RuleBuilder.safeDefault.toNormRuleBuilder
  | unsafeDefault => RuleBuilder.unsafeDefault.toNormRuleBuilder
  | normDefault => RuleBuilder.normDefault

def toBuilderName : Builder → RuleName.Builder
  | apply => RuleName.Builder.apply
  | simp => RuleName.Builder.simp
  | unfold => RuleName.Builder.unfold
  | tactic .. => RuleName.Builder.tactic
  | constructors => RuleName.Builder.constructors
  | forward .. => RuleName.Builder.forward
  | cases => RuleName.Builder.cases
  | safeDefault => RuleName.Builder.safeDefault
  | unsafeDefault => RuleName.Builder.unsafeDefault
  | normDefault => RuleName.Builder.normDefault

end Builder


open Builder in
def defaultBuilderForPhase : RuleName.Phase → Builder
  | RuleName.Phase.safe => safeDefault
  | RuleName.Phase.norm => normDefault
  | RuleName.Phase.«unsafe» => unsafeDefault


namespace Parser

syntax ruleSetsFeature := "(" &"rule_sets" "[" ident,+,? "]" ")"

end Parser

structure RuleSets where
  ruleSets : Array Name
  deriving Inhabited

namespace RuleSets

instance : ToString RuleSets where
  toString rs := s!"(rule_sets [{String.joinSep ", " $ rs.ruleSets.map toString}])"

def parse : Syntax → RuleSets
  | `(Parser.ruleSetsFeature| (rule_sets [$ns:ident,*])) =>
    ⟨(ns : Array Syntax).map (·.getId)⟩
  | _ => unreachable!

end RuleSets


namespace Parser

declare_syntax_cat Aesop.feature (behavior := symbol)

-- NOTE: This grammar has overlapping rules (`ident`, `Aesop.builder` and
-- `Aesop.phase` since they can all consist of a single ident). For ambiguous
-- parses, a `choice` node with two children is created; one being a
-- `featPhase` or `featBuilder` node and the second being a `featIdent` node.
-- When we process these `choice` nodes, we select the non-`ident` one.
syntax (name := featPhase) Aesop.phase : Aesop.feature
syntax (name := featPriority) Aesop.priority : Aesop.feature
syntax (name := featBuilder) Aesop.builder : Aesop.feature
syntax (name := featRuleSets) ruleSetsFeature : Aesop.feature
syntax (name := featIdent) ident : Aesop.feature

end Parser

inductive Feature
  | phase (p : RuleName.Phase)
  | priority (p : Priority)
  | builder (b : Builder)
  | name (n : Name)
  | ruleSets (rs : RuleSets)
  deriving Inhabited

namespace Feature

instance : ToString Feature where
  toString
    | phase p => toString p
    | priority p => toString p
    | builder b => toString b
    | name n => toString n
    | ruleSets rs => toString rs

partial def parse : Syntax → ParseT m Feature
  | `(feature| $p:Aesop.priority) => priority <$> Priority.parse p
  | `(feature| $p:Aesop.phase) => return phase $ parsePhaseName p
  | `(feature| $b:Aesop.builder) => builder <$> Builder.parse b
  | `(feature| $rs:ruleSetsFeature) => return ruleSets $ RuleSets.parse rs
  | `(feature| $i:ident) => return name i.getId
  | stx =>
    if stx.isOfKind choiceKind then
      let nonIdentAlts :=
        stx.getArgs.filter λ stx => ! stx.isOfKind ``Parser.featIdent
      if nonIdentAlts.size != 1 then
        panic! "expected choice node with exactly one non-ident child"
      else
        parse nonIdentAlts[0]
    else
      unreachable!

end Feature


namespace Parser

declare_syntax_cat Aesop.rule_expr (behavior := symbol)

syntax Aesop.feature : Aesop.rule_expr
syntax Aesop.feature Aesop.rule_expr : Aesop.rule_expr
syntax Aesop.feature "[" Aesop.rule_expr,+,? "]" : Aesop.rule_expr

end Parser


inductive RuleExpr
  | node (f : Feature) (children : Array RuleExpr)
  deriving Inhabited

namespace RuleExpr

protected partial def toString : RuleExpr → String
  | node f children =>
    let cont :=
      if children.isEmpty then
        ""
      else if children.size = 1 then
        RuleExpr.toString children[0]
      else
        "[" ++ String.joinSep ", " (children.map RuleExpr.toString) ++ "]"
    String.joinSep " " #[toString f, cont]

instance : ToString RuleExpr :=
  ⟨RuleExpr.toString⟩

partial def parse : Syntax → ParseT m RuleExpr
  | `(rule_expr| $f:Aesop.feature $e:Aesop.rule_expr) => do
    return node (← Feature.parse f) #[← parse e]
  | `(rule_expr| $f:Aesop.feature [ $es:Aesop.rule_expr,* ]) => do
    return node (← Feature.parse f) (← (es : Array Syntax).mapM parse)
  | `(rule_expr| $f:Aesop.feature) => do
    return node (← Feature.parse f) #[]
  | _ => unreachable!

-- Fold the branches of a `RuleExpr`. We treat each branch as a list of features
-- which we fold over. The result is an array containing one result per branch.
partial def foldBranchesM {m} [Monad m] (f : σ → Feature → m σ) (init : σ)
    (e : RuleExpr) : m (Array σ) :=
  go init #[] e
  where
    go (c : σ) (acc : Array σ) : RuleExpr → m (Array σ)
      | RuleExpr.node feat cs => do
        let c ← f c feat
        if cs.isEmpty then
          return acc.push c
        else
          cs.foldlM (init := acc) (go c)

end RuleExpr


structure RuleConfig (f : Type → Type) where
  ident : f RuleIdent
  phase : f RuleName.Phase
  priority : f Priority
  builder : f Builder
  ruleSets : RuleSets

namespace RuleConfig

def toStringOption (c : RuleConfig Option) : String :=
  String.joinSep " " #[
    optionToString c.ident,
    optionToString c.phase,
    optionToString c.priority,
    optionToString c.builder,
    toString c.ruleSets
  ]
  where
    optionToString {α} [ToString α] : Option α → String
      | none => ""
      | some a => toString a

def toStringId (c : RuleConfig Id) : String :=
  String.joinSep " "
    #[toString c.ident, toString c.phase, toString c.builder, toString c.ruleSets]

def getPenalty (phase : RuleName.Phase) (c : RuleConfig Id) : m Int := do
  let (some penalty) := c.priority.toInt? | throwError
    "aesop: {phase} rules must specify an integer penalty (not a success probability)"
  return penalty

def getSuccessProbability (c : RuleConfig Id) : m Percent := do
  let (some prob) := c.priority.toPercent? | throwError
    "aesop: unsafe rules must specify a success probability (not an integer penalty)"
  return prob

def buildLocalRule (c : RuleConfig Id) (goal : MVarId) :
    MetaM (MVarId × RuleSetMember × Array RuleSetName) := do
  match c.phase with
  | phase@RuleName.Phase.safe =>
    let penalty ← c.getPenalty phase
    let (goal, res) ← runRegularBuilder phase c.builder
    let rule := RuleSetMember'.safeRule {
      name := c.ident.toRuleName phase res.builder
      tac := res.tac
      indexingMode := res.indexingMode
      usesBranchState := res.mayUseBranchState
      extra := { penalty, safety := Safety.safe }
      -- TODO support 'almost safe' rules
    }
    return (goal, rule, c.ruleSets.ruleSets)
  | phase@RuleName.Phase.«unsafe» =>
    let successProbability ← c.getSuccessProbability
    let (goal, res) ← runRegularBuilder phase c.builder
    let rule := RuleSetMember'.unsafeRule {
      name := c.ident.toRuleName phase res.builder
      tac := res.tac
      indexingMode := res.indexingMode
      usesBranchState := res.mayUseBranchState
      extra := { successProbability }
    }
    return (goal, rule, c.ruleSets.ruleSets)
  | phase@RuleName.Phase.norm =>
    let penalty ← c.getPenalty phase
    let (goal, res) ← c.builder.toNormRuleBuilder c.ident goal
    match res with
    | NormRuleBuilderResult.regular res =>
      let rule := RuleSetMember'.normRule {
        name := c.ident.toRuleName phase res.builder
        tac := res.tac
        indexingMode := res.indexingMode
        usesBranchState := res.mayUseBranchState
        extra := { penalty }
      }
      return (goal, rule, c.ruleSets.ruleSets)
    | NormRuleBuilderResult.simp res =>
      let rule := RuleSetMember'.normSimpRule {
        name := c.ident.toRuleName phase res.builder
        entries := res.entries
      }
      return (goal, rule, c.ruleSets.ruleSets)
  where
    runRegularBuilder (phase : RuleName.Phase) (b : Builder) :
        MetaM (MVarId × RegularRuleBuilderResult) := do
      let (some b) := b.toRegularRuleBuilder | throwError
        "aesop: builder {b} cannot be used for {phase} rules"
      b c.ident goal

-- Precondition: `c.ident = RuleIdent.const _`.
def buildGlobalRule (c : RuleConfig Id) :
    MetaM (RuleSetMember × Array RuleSetName) :=
  Prod.snd <$> buildLocalRule c ⟨`_dummy⟩
  -- NOTE: We assume here that global rule builders ignore the dummy
  -- metavariable.

def toRuleNameFilter (c : RuleConfig Option) :
    m (RuleSetNameFilter × RuleNameFilter) := do
  let (some ident) := c.ident | throwError
    "aesop: rule name not specified"
  let builders :=
    match c.builder with
    | none => #[]
    | some b => #[b.toBuilderName]
  let phases :=
    match c.phase with
    | none => #[]
    | some p => #[p]
  let ruleSetNames := c.ruleSets.ruleSets
  return ({ ruleSetNames }, { ident, builders, phases })

end RuleConfig


namespace RuleExpr

def toAdditionalRules (e : RuleExpr) (init : RuleConfig Option)
    (nameToIdent : Name → m RuleIdent) : m (Array (RuleConfig Id)) := do
  let cs ← e.foldBranchesM (init := init) go
  cs.mapM finish
  where
    go (r : RuleConfig Option) : Feature → m (RuleConfig Option)
      | Feature.phase p => do
        if let (some previous) := r.phase then throwError
          "aesop: duplicate phase declaration: '{p}'\n(previous declaration: '{previous}')"
        return { r with phase := some p }
      | Feature.priority p => do
        if let (some previous) := r.priority then throwError
          "aesop: duplicate priority declaration: '{p}'\n(previous declaration: '{previous}')"
        return { r with priority := some p }
      | Feature.builder b => do
        if let (some previous) := r.builder then throwError
          "aesop: duplicate builder declaration: '{b}'\n(previous declaration: '{previous}')"
        return { r with builder := some b }
      | Feature.name n => do
        if let (some previous) := r.ident then throwError
          "aesop: duplicate rule name: '{n}'\n(previous rule name: '{previous}')"
        let ident ← nameToIdent n
        return { r with ident }
      | Feature.ruleSets newRuleSets =>
        have ord : Ord RuleSetName := ⟨Name.quickCmp⟩
        let ruleSets :=
          ⟨Array.mergeSortedFilteringDuplicates r.ruleSets.ruleSets $
            newRuleSets.ruleSets.qsort ord.isLT⟩
        return { r with ruleSets }

    getPhaseAndPriority (c : RuleConfig Option) :
        m (RuleName.Phase × Priority) :=
      match c.phase, c.priority with
      | none, none =>
        throwError "aesop: phase (safe/unsafe/norm) not specified."
      | some RuleName.Phase.unsafe, none =>
        throwError "aesop: unsafe rules must specify a success probability ('x%')."
      | some phase@RuleName.Phase.safe, none =>
        return (phase, Priority.int defaultSafePenalty)
      | some phase@RuleName.Phase.norm, none =>
        return (phase, Priority.int defaultNormPenalty)
      | some phase, some prio =>
        return (phase, prio)
      | none, some prio@(Priority.percent prob) =>
        return (RuleName.Phase.unsafe, prio)
      | none, some _ =>
        throwError "aesop: phase (safe/unsafe/norm) not specified."

    finish (c : RuleConfig Option) : m (RuleConfig Id) := do
      let (some ident) := c.ident | throwError
        "aesop: rule name not specified"
      let (phase, priority) ← getPhaseAndPriority c
      let builder :=
        c.builder.getD $ defaultBuilderForPhase phase
      let ruleSets :=
        if c.ruleSets.ruleSets.isEmpty then
          ⟨#[defaultRuleSetName]⟩
        else
          c.ruleSets
      return { ident, phase, priority, builder, ruleSets }

def toAdditionalGlobalRules (decl : Name) (e : RuleExpr) :
    m (Array (RuleConfig Id)) :=
  let init := {
    ident := RuleIdent.const decl
    phase := none
    priority := none
    builder := none
    ruleSets := ⟨#[]⟩
  }
  let nameToIdent n := throwError
    "aesop: rule name '{n}' not allowed in aesop attribute.\n(Perhaps you misspelled a builder or phase.)"
  toAdditionalRules e init nameToIdent

def buildAdditionalGlobalRules (decl : Name) (e : RuleExpr) :
    MetaM (Array (RuleSetMember × Array RuleSetName)) := do
  (← e.toAdditionalGlobalRules decl).mapM (·.buildGlobalRule)

def toAdditionalLocalRules (goal : MVarId) (e : RuleExpr) :
    MetaM (Array (RuleConfig Id)) :=
  let init := {
    ident := none
    phase := none
    priority := none
    builder := none
    ruleSets := ⟨#[]⟩
  }
  let nameToIdent n := withMVarContext goal $ RuleIdent.ofName n
  toAdditionalRules e init nameToIdent

def buildAdditionalLocalRules (goal : MVarId) (e : RuleExpr) :
    MetaM (MVarId × Array (RuleSetMember × Array RuleSetName)) := do
  let configs ← e.toAdditionalLocalRules goal
  let mut goal := goal
  let mut rs := Array.mkEmpty configs.size
  for config in configs do
    let (goal', rule) ← config.buildLocalRule goal
    goal := goal'
    rs := rs.push rule
  return (goal, rs)

def toRuleNameFilters (e : RuleExpr) (nameToIdent : Name → m RuleIdent) :
    m (Array (RuleSetNameFilter × RuleNameFilter)) := do
  let initialConfig := {
      ident := none
      phase := none
      priority := none
      builder := none
      ruleSets := ⟨#[]⟩
  }
  let configs ← e.foldBranchesM (init := initialConfig) go
  configs.mapM (·.toRuleNameFilter)
  where
    go (r : RuleConfig Option) : Feature → m (RuleConfig Option)
      | Feature.phase p => do
        if let (some previous) := r.phase then throwError
          "aesop: duplicate phase declaration: '{p}'\n(previous declaration: '{previous}')"
        return { r with phase := some p }
      | Feature.priority prio =>
        throwError "aesop: unexpected priority '{prio}'"
      | Feature.name n => do
        if let (some previous) := r.ident then throwError
          "aesop: duplicate rule name: '{n}'\n(previous rule name: '{previous}')"
        return { r with ident := (← nameToIdent n) }
      | Feature.builder b => do
        if let (some previous) := r.builder then throwError
          "aesop: duplicate builder declaration: '{b}'\n(previous declaration: '{previous}')"
        return { r with builder := some b }
      | Feature.ruleSets newRuleSets =>
        have ord : Ord RuleSetName := ⟨Name.quickCmp⟩
        let ruleSets :=
          ⟨Array.mergeSortedFilteringDuplicates r.ruleSets.ruleSets $
            newRuleSets.ruleSets.qsort ord.isLT⟩
        return { r with ruleSets }

def toGlobalRuleNameFilters (e : RuleExpr) :
    m (Array (RuleSetNameFilter × RuleNameFilter)) :=
  e.toRuleNameFilters λ n => return RuleIdent.const n

def toLocalRuleNameFilters (goal : MVarId) (e : RuleExpr) :
    MetaM (Array (RuleSetNameFilter × RuleNameFilter)) :=
  e.toRuleNameFilters λ n => withMVarContext goal $ RuleIdent.ofName n

end Aesop.Frontend.RuleExpr