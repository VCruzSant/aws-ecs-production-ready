# Scanners

`make scan` (Trivy 0.76.2 and Checkov 3.4.5, run from their Docker images). Exit code 0:

```
== trivy config infra
== checkov infra
Passed checks: 209, Failed checks: 0, Skipped checks: 29
== trivy image
```
