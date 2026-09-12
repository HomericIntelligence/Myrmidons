# Execution pools for Homeric Fleet

`ExecutionPool` is desired state under `myrmidons/v1`. Agamemnon admits work and
reconciles workers. Hephaestus executes admitted work. Myrmidons stores no live
claims, allocation IDs, authentication material, conversation history, or status.
Odysseus can use `metadata.displayName` and stable worker IDs for display.

## Integration boundaries

The [Odysseus architecture](https://github.com/HomericIntelligence/Odysseus/blob/main/docs/architecture.md)
defines the runtime owners. These manifests supply configuration to those owners;
they do not dispatch tasks or record execution results.

| Component | Relationship to this dataset |
| --- | --- |
| Odysseus | Displays pools and workers through the orchestration interfaces |
| Agamemnon | Resolves profiles, admits work, and owns claims, leases, and generations |
| Keystone | Carries admitted role-addressed work and worker facts |
| Hephaestus | Supervises each runtime and enforces its workspace and execution boundary |
| AchaeanFleet | Supplies pinned images with independently checked provenance |

Provider authentication, private inputs, journals, and runtime state belong outside
source workspaces. Consumers must keep these roots disjoint and exclude worker
`.fleet-runtime` directories from source snapshots. Profile references declare the
required bindings; they do not prove that any runtime boundary has been enforced.

## Select a target

The supplied targets describe the same required capacity with different laptop
backends. Select exactly one target for an experiment or deployment:

```bash
just validate-fleet homeric-fleet-native
just validate-fleet homeric-fleet-container
```

Each target declares 108 conversations across five Codex runtimes. This is desired
capacity. It is not evidence that workers exist or that 108 agents are active.
Both laptop pools have `exclusiveGroup: laptop-comparison`; a Fleet that selects
both fails validation. Separate build workers do not contribute agent slots.

| Pool | Workers × conversations | Allocation per worker | Supervision | Workload |
| --- | ---: | --- | --- | --- |
| `laptop-native` or `laptop-container` | 1 × 12 | 8 CPUs / 12 GiB | 2 CPUs / 4 GiB | 6 CPUs / 8 GiB |
| `m1-agents` | 2 × 24 | 72 CPUs / 288 GiB | 8 CPUs / 32 GiB | 64 CPUs / 256 GiB |
| `m2-agents` | 2 × 24 | 72 CPUs / 288 GiB | 8 CPUs / 32 GiB | 64 CPUs / 256 GiB |
| `m1-builds` | 1 × 0 | 18 CPUs / 72 GiB | 2 CPUs / 8 GiB | 16 CPUs / 64 GiB |
| `m2-builds` | 1 × 0 | 18 CPUs / 72 GiB | 2 CPUs / 8 GiB | 16 CPUs / 64 GiB |

These are initial requested budgets, not measured requirements. The native laptop
budget is an admission estimate; it does not establish macOS process limits. The
container comparison requires a Linux VM with the declared aggregate resources.
Measure host headroom and worker overhead before enabling either laptop profile.
Conversations in one runtime do not have independent CPU or memory cgroups.

M1 and M2 are Linux Slurm clusters. The profiles request zero GPUs, Pyxis images,
and authenticated allocation attachment. M1 selects `main`; M2 selects `cpuonly`.
Verify partition availability, platform compatibility, actual allocation resources,
attachment, and provider connectivity before admission. Do not silently reduce a
request or substitute a different backend.

## Document and reference contracts

- `pools/<name>.yaml` contains an `ExecutionPool`; `metadata.name` is its stable ID.
- `spec.backend` is `native`, `container`, or `slurm`; `purpose` is `agents` or `builds`.
- `allocation`, `overhead`, and `workload` apply to each worker. Their CPU and memory
  values are integers; overhead plus workload must not exceed allocation.
- `workers` equals the number of `workerProfiles`. Agent capacity is
  `workers * conversationsPerWorker`. Build pools require zero conversations.
- Each `workerProfiles` entry has `workerId`, `privateHomeRef`, and
  `permissionProfileRef`. Agent workers also require a distinct `authProfileRef`.
  Build workers must not receive provider authentication references.
- Agent pools pin Codex `0.153.4`, use `independent-native-login`, and set
  `nestedAgents: false`. The native login belongs to the runtime, not to each conversation.
- `container.image` is null until a real image build supplies a digest reference.
  Non-null references must use `@sha256:`; mutable tags fail validation.
- `Fleet.spec.executionPools` selects pool names. `expectedCapacity` and
  `expectedCapacityByHost` are checked against those pools, excluding build capacity.

Private home, authentication, and permission references are opaque names. The
trusted operator configuration resolves them outside this repository. The
consumer must reject missing bindings, reused homes, or unverified workspace
isolation. Distinct reference names alone do not prove that their bound paths
or credentials differ. Never copy one native refresh bundle across runtimes.
Permission profiles must enforce per-conversation workspace boundaries; a working
directory alone does not provide isolation.

Existing Agent and Fleet documents remain valid. Agents and inline Fleet members
can use `program: codex` and optional `poolRef`, `executionDomain`, and `hmasRole`.
`role` remains the administrative `member`/`admin` field. Domain and HMAS role are
extensible slugs, such as `pipeline` and `task-agent`; they do not encode hierarchy
depth or model selection.

A member's `poolRef` takes precedence over `Fleet.spec.poolRef`. The Fleet default
applies only when the member omits its own reference. A reference must resolve to
an agent pool with a matching program and host. When `executionPools` is present,
each member's resolved pool must be selected there. Fleet agent `ref` values keep
their existing `host/filename-stem` meaning.

A Fleet can select pools without listing agents in advance. Agamemnon must assign
each admitted logical agent its own identity, lease, task, workspace, and
conversation. Sharing a runtime does not combine these identities. Consumers
must explicitly support `ExecutionPool`; they must not silently ignore it.

The work subject remains `hi.myrmidon.{executionDomain}.{hmasRole}.task.{taskId}`.
The manifest API is `myrmidons/v1`; runtime envelopes use `hi/fleet/v1`.

## Validation and activation

```bash
just validate-dataset
just test-pools
just validate-runnable homeric-fleet-native
```

The last command intentionally fails for the supplied profiles. Every admission
flag is false, and every container image is null. This prevents unresolved image
pins from passing the offline runnable check. That check also requires an explicit
Fleet target, so it cannot combine the laptop alternatives by accident.

Before activation, the consumer must also verify image provenance, profile bindings,
authentication, transport, platform support, resource enforcement, and durable
orchestration. Offline validation makes no claim about these live checks. A
syntactically valid digest is not proof that an image exists or passed acceptance.
Myrmidons does not issue commands or change admission at runtime.

All schedules are disabled. Their saved policy uses ISO weekdays 1 through 5 and
`America/Los_Angeles`, with submission at `08:00`, drain at `17:00`, and termination
at `18:00`. Enable scheduling only after acceptance. Agamemnon must handle daylight
saving time, restarts, laptop sleep, and the allocation termination deadline.
The offline validator checks the timezone and time order, not scheduler behavior.

The existing schema validator entry point now covers Agents, Fleets, and pools.
The `just` recipes and pre-commit checks run this validation. Dataset archives
include `pools/` when present, while old datasets without pools still package.
Canonical `just package` normalizes tar ownership and timestamps, writes and
checks `dist/SHA256SUMS`, and extracts with the system tar reader. It compares
every included source tree and `RELEASE_INFO` byte for byte before success.
These checks validate dataset delivery only; they do not validate a worker
image or authorize admission.

Accepted ADRs are unchanged. The compatible additions do not rename or remove
existing required fields. Runtime integration follows the owning component's
review process.
