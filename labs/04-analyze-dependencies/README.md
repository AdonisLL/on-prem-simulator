# 04 - Analyze dependencies

The scheduled workload on `dc01` alternates requests between both web servers.
Each web request reads SQL, and participant inventory adjustments create writes.
The logical traffic is the same whether the servers are Azure VMs or inner
Hyper-V VMs.

## Exercise

1. Confirm `OnPremLab-SyntheticTraffic` is running on `dc01`.
2. Make inventory changes through both web sites.
3. Allow the documented dependency aggregation interval to pass.
4. Open dependency analysis for the application group.
5. Identify client-to-web, web-to-SQL, and domain/DNS dependencies.

If web-to-SQL is absent, check active traffic first, then verify that dependency
collection is enabled and credentials are valid. Avoid generating artificial
NSG-wide traffic; the goal is to observe real application connections.

## Discussion

- Which servers must move together?
- Which dependencies are infrastructure-only versus application runtime?
- What would break if SQL moved before connection and identity changes?
- Why are two independent IIS servers not proof of application high
  availability?

## Checkpoint

Capture a dependency view that shows both IIS servers communicating with SQL.
Record the observation window so another participant can reproduce it.
