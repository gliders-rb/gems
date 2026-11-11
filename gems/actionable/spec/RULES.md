# Rule to spec map

Every `AC-B#` behaviour rule and the spec files holding a tagged example for it.
Written by the slice 13 conformance sweep: 197 rules (196 bullets plus the inline allowss), all with at least one tagged example.

| Rule | Spec files |
|---|---|
| predicates | spec/actionable/result_spec.rb |
| defaultcodes | spec/actionable/result_spec.rb |
| status | spec/actionable/result_spec.rb |
| resultdefaults | spec/actionable/result_spec.rb |
| metadataonly | spec/actionable/result_spec.rb |
| inspect | spec/actionable/result_spec.rb |
| toh | spec/actionable/result_spec.rb |
| toapi | spec/actionable/result_spec.rb |
| delegation | spec/actionable/result_spec.rb |
| patternmatch | spec/actionable/result_spec.rb |
| absorb | spec/actionable/result_spec.rb |
| fieldsset | spec/actionable/result_spec.rb |
| equality | spec/actionable/result_spec.rb |
| errorsapi | spec/actionable/result_spec.rb |
| plainverbs | spec/actionable/action_verbs_spec.rb |
| lastwins | spec/actionable/action_verbs_spec.rb |
| bangverbs | spec/actionable/action_verbs_spec.rb |
| failerrors | spec/actionable/action_verbs_spec.rb |
| succeedkw | spec/actionable/output_spec.rb |
| failwith | spec/actionable/action_verbs_spec.rb |
| codeformat | spec/actionable/action_verbs_spec.rb |
| failshadow | spec/actionable/action_verbs_spec.rb |
| skipoutput | spec/actionable/output_spec.rb |
| halttag | spec/actionable/action_verbs_spec.rb |
| verbsprivate | spec/actionable/action_verbs_spec.rb |
| resultreserved | spec/actionable/output_spec.rb |
| hashoutput | spec/actionable/output_spec.rb |
| stepdecl | spec/actionable/action_steps_spec.rb, spec/actionable/lifecycle_spec.rb, spec/actionable/nested_spec.rb |
| redeclare | spec/actionable/action_steps_spec.rb, spec/actionable/case_step_spec.rb, spec/actionable/lifecycle_spec.rb |
| subclassoverride | spec/actionable/action_steps_spec.rb, spec/actionable/lifecycle_spec.rb |
| guards | spec/actionable/action_steps_spec.rb |
| privatesteps | spec/actionable/action_steps_spec.rb |
| snapshot | spec/actionable/action_steps_spec.rb, spec/actionable/lifecycle_spec.rb |
| measurevalidate | spec/actionable/guardrails_spec.rb |
| instances | spec/actionable/action_steps_spec.rb |
| lifecycle | spec/actionable/lifecycle_spec.rb |
| hookverbs | spec/actionable/lifecycle_spec.rb |
| recovery | spec/actionable/lifecycle_spec.rb |
| alwayshalt | spec/actionable/lifecycle_spec.rb |
| hookaction | spec/actionable/nested_spec.rb |
| exceptionhooks | spec/actionable/lifecycle_spec.rb |
| missingmethod | spec/actionable/guardrails_spec.rb, spec/actionable/lifecycle_spec.rb |
| runorder | spec/actionable/guardrails_spec.rb |
| freeformrun | spec/actionable/action_steps_spec.rb |
| sampling | spec/actionable/guardrails_spec.rb |
| reservedout | spec/actionable/declared_outcomes_spec.rb, spec/actionable/output_spec.rb |
| outputdecl | spec/actionable/output_spec.rb |
| refresh | spec/actionable/output_spec.rb |
| invalidout | spec/actionable/output_spec.rb |
| coerceout | spec/actionable/output_spec.rb |
| kwargswin | spec/actionable/lifecycle_spec.rb, spec/actionable/output_spec.rb |
| invalidoutstays | spec/actionable/lifecycle_spec.rb, spec/actionable/output_spec.rb |
| hookoutput | spec/actionable/lifecycle_spec.rb |
| freeformout | spec/actionable/output_spec.rb |
| failureoutput | spec/actionable/output_spec.rb |
| inputdecl | spec/actionable/input_spec.rb |
| typedrun | spec/actionable/input_spec.rb |
| invalidinput | spec/actionable/input_spec.rb |
| inputinstance | spec/actionable/input_spec.rb |
| unknownraise | spec/actionable/input_spec.rb |
| nestedinput | spec/actionable/input_spec.rb |
| inputnoblock | spec/actionable/input_spec.rb |
| inputfor | spec/actionable/input_spec.rb |
| dispatchunmatched | spec/actionable/input_spec.rb |
| dispatchinstance | spec/actionable/input_spec.rb |
| dispatchprecedence | spec/actionable/input_spec.rb |
| inputdispatch | spec/actionable/input_spec.rb |
| dispatchruntype | spec/conformance/sweep_spec.rb |
| valuematch | spec/actionable/case_step_spec.rb, spec/actionable/value_match_spec.rb |
| casestep | spec/actionable/case_step_spec.rb |
| casenomatch | spec/actionable/case_step_spec.rb |
| caseguard | spec/actionable/case_step_spec.rb |
| caserequired | spec/actionable/case_step_spec.rb |
| casekind | spec/actionable/case_step_spec.rb |
| nestedrun | spec/actionable/nested_spec.rb |
| nestedabsorb | spec/actionable/nested_spec.rb |
| nestedfail | spec/actionable/declared_outcomes_spec.rb, spec/actionable/nested_spec.rb |
| nesteddeclare | spec/actionable/declared_outcomes_spec.rb |
| nestedskip | spec/actionable/declared_outcomes_spec.rb |
| nestedhistory | spec/conformance/sweep_spec.rb |
| nestedguard | spec/actionable/nested_spec.rb |
| nestedinvalidinput | spec/actionable/declared_outcomes_spec.rb, spec/actionable/nested_spec.rb |
| declare | spec/actionable/declared_outcomes_spec.rb |
| declread | spec/actionable/declared_outcomes_spec.rb |
| declcarry | spec/actionable/declared_outcomes_spec.rb |
| declgem | spec/actionable/declared_outcomes_spec.rb |
| declstrict | spec/actionable/declared_outcomes_spec.rb |
| declstrictskip | spec/actionable/declared_outcomes_spec.rb |
| allowsf | spec/actionable/declared_outcomes_spec.rb |
| declorder | spec/actionable/declared_outcomes_spec.rb, spec/actionable/typed_outcomes_spec.rb |
| typedflag | spec/actionable/typed_outcomes_spec.rb |
| typedschema | spec/actionable/typed_outcomes_spec.rb |
| typedempty | spec/actionable/typed_outcomes_spec.rb |
| outputkw | spec/actionable/typed_outcomes_spec.rb |
| outputrefused | spec/actionable/typed_outcomes_spec.rb |
| resultclasses | spec/actionable/typed_outcomes_spec.rb |
| typedequality | spec/actionable/typed_outcomes_spec.rb |
| nestedtyped | spec/actionable/typed_outcomes_spec.rb |
| typedstubs | spec/coverage/typed_stubs_spec.rb |
| measurenone | spec/actionable/measurement_spec.rb |
| historyentries | spec/actionable/measurement_spec.rb |
| historycode | spec/actionable/measurement_spec.rb |
| historyapi | spec/actionable/history_spec.rb |
| cascade | spec/actionable/measurement_spec.rb |
| fiberlocal | spec/actionable/measurement_spec.rb |
| sampled | spec/actionable/measurement_spec.rb |
| measureinherit | spec/actionable/guardrails_spec.rb, spec/actionable/measurement_spec.rb |
| hooktimes | spec/conformance/sweep_spec.rb |
| runeach | spec/actionable/action_steps_spec.rb |
| batchapi | spec/actionable/action_steps_spec.rb |
| registry | spec/actionable/action_steps_spec.rb, spec/actionable/registry_spec.rb |
| describe | spec/actionable/declared_outcomes_spec.rb, spec/actionable/describe_spec.rb |
| describetext | spec/actionable/declared_outcomes_spec.rb, spec/actionable/describe_spec.rb |
| verbcheck | spec/actionable/verb_position_spec.rb |
| verbtail | spec/actionable/verb_position_spec.rb |
| verboffense | spec/actionable/verb_position_spec.rb |
| verbscope | spec/actionable/verb_position_spec.rb |
| verbonce | spec/actionable/verb_position_spec.rb |
| verbswitch | spec/actionable/verb_position_spec.rb |
| prism | spec/actionable/verb_position_spec.rb |
| cop | spec/actionable/rubocop_cop_spec.rb, spec/actionable/verb_position_spec.rb |
| copscope | spec/actionable/rubocop_cop_spec.rb |
| copbases | spec/actionable/rubocop_cop_spec.rb |
| copparse | spec/actionable/rubocop_cop_spec.rb |
| copplugin | spec/actionable/rubocop_cop_spec.rb |
| railsload | spec/rails/load_spec.rb |
| transactional | spec/rails/transactional_spec.rb |
| txrun | spec/rails/transactional_spec.rb |
| txsavepoint | spec/rails/transactional_spec.rb |
| aftercommit | spec/rails/after_commit_spec.rb |
| aftercommitwhen | spec/rails/after_commit_spec.rb |
| aftercommitnature | spec/rails/after_commit_spec.rb |
| aftercommitdescribe | spec/rails/after_commit_spec.rb |
| proxy | spec/rails/proxy_validator_spec.rb |
| railsci | spec/rails/after_commit_spec.rb |
| jobdisposition | spec/job/job_spec.rb |
| jobhonor | spec/job/job_spec.rb |
| honormacro | spec/job/job_spec.rb |
| mixin | spec/job/active_job_spec.rb, spec/job/job_spec.rb, spec/job/sidekiq_spec.rb |
| retryfailure | spec/job/active_job_spec.rb, spec/job/job_spec.rb, spec/job/sidekiq_spec.rb |
| jobpure | spec/job/active_job_spec.rb, spec/job/job_spec.rb, spec/job/sidekiq_spec.rb |
| rspecload | spec/actionable/rspec_matcher_spec.rb |
| matcher | spec/actionable/rspec_matcher_spec.rb |
| matchsemantics | spec/actionable/rspec_matcher_spec.rb |
| matchneg | spec/actionable/rspec_matcher_spec.rb |
| matchdeclared | spec/actionable/rspec_matcher_spec.rb |
| matchmessages | spec/actionable/rspec_matcher_spec.rb |
| matchbacktrace | spec/actionable/rspec_matcher_spec.rb |
| stubs | spec/actionable/rspec_stubs_spec.rb |
| stubbuilders | spec/actionable/rspec_stubs_spec.rb |
| stubdeclared | spec/actionable/rspec_stubs_spec.rb |
| stubshape | spec/actionable/rspec_stubs_spec.rb |
| stubparent | spec/actionable/rspec_stubs_spec.rb |
| stubcoverage | spec/actionable/rspec_stubs_spec.rb |
| covload | spec/coverage/recording_spec.rb |
| covrecord | spec/coverage/recording_spec.rb |
| covoutcomes | spec/coverage/outcomes_spec.rb |
| covsettings | spec/coverage/recording_spec.rb |
| covactions | spec/coverage/outcomes_spec.rb |
| covreport | spec/coverage/report_spec.rb |
| covtext | spec/coverage/report_spec.rb |
| covbaseline | spec/coverage/report_spec.rb |
| covmessage | spec/coverage/report_spec.rb |
| covbaselinewrite | spec/coverage/report_spec.rb |
| covreportbang | spec/coverage/report_spec.rb |
| covshards | spec/coverage/recording_spec.rb |
| covsuite | spec/coverage/report_spec.rb |
| covpartial | spec/conformance/sweep_spec.rb |
| rbsargs | spec/actionable/rbs_spec.rb |
| rbsancestors | spec/actionable/rbs_spec.rb |
| rbsrun | spec/actionable/rbs_spec.rb |
| rbsinput | spec/actionable/rbs_spec.rb |
| rbsivars | spec/actionable/rbs_spec.rb |
| rbsaliases | spec/actionable/rbs_spec.rb |
| rbstyped | spec/actionable/rbs_spec.rb |
| rbsformat | spec/actionable/rbs_spec.rb |
| rbsshipped | spec/sigs/shipped_sig_spec.rb |
| gemshape | spec/gemspec_spec.rb |
| docs | spec/adapter_sigs/docs_names_spec.rb, spec/docs/docs_check_spec.rb |
| skill | spec/skill_spec.rb |
| bench | spec/bench_spec.rb |
| ci | spec/conformance/sweep_spec.rb |
| sigratchet | spec/sigs/sig_guards_spec.rb |
| adaptersigspec | spec/adapter_sigs/adapter_sig_spec.rb |
| runseam | spec/actionable/action_steps_spec.rb |
| recordseam | spec/actionable/action_steps_spec.rb, spec/actionable/case_step_spec.rb, spec/actionable/lifecycle_spec.rb, spec/actionable/nested_spec.rb |
| recordreturn | spec/actionable/action_steps_spec.rb, spec/actionable/measurement_spec.rb |
| runnerinstance | spec/actionable/action_steps_spec.rb |
| resultidentity | spec/actionable/measurement_spec.rb |
| stepshapes | spec/actionable/action_steps_spec.rb |
| anonlabel | spec/actionable/action_steps_spec.rb |
| schemareaders | spec/conformance/sweep_spec.rb |
| errorsshape | spec/conformance/sweep_spec.rb |
| outputshape | spec/conformance/sweep_spec.rb |
| successnometa | spec/conformance/sweep_spec.rb |
| abstractreaders | spec/conformance/sweep_spec.rb |

The inline rule allowss (defined beside allowsf) is tagged in spec/actionable/declared_outcomes_spec.rb.
