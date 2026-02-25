# Zuul 프로덕션 환경에서의 무중단 업그레이드 전략

## 도입: 프로덕션 업그레이드와 다운타임 문제

실제 프로덕션 환경에서 시스템을 업그레이드할 때 가장 우려되는 부분은 바로 **서비스 중단(Downtime)**입니다. 이 글에서는 수백 개의 CI/CD 파이프라인이 돌아가는 상황에서, Zuul이 어떻게 서비스 중단 문제를 해결하고 안전하게 업그레이드를 수행하는지 다뤄보겠습니다.

---

## 롤링 업그레이드(Rolling Upgrade)란?

전체 시스템의 전원을 한 번에 내리는 대신, **여러 컴포넌트를 하나씩 순차적으로 껐다 켜면서 패치를 적용하는 방식**을 **롤링 업그레이드(Rolling Upgrade)**라고 합니다.

마이크로서비스 아키텍처(MSA)를 채택한 Zuul은 각 역할이 스케줄러, 실행기, 병합기 등으로 철저히 분리되어 있습니다. 만약 시스템에 각 컴포넌트가 이중화(HA)되어 두 개 이상 실행 중이라면, 사용자는 시스템이 점검 중인지도 모르는 상태로 **다운타임 없는 업그레이드**가 가능합니다.

---

## 사전 확인: 컴포넌트 활성화 상태 점검

롤링 업그레이드를 시작하기 전, 현재 시스템에 여러 대의 컴포넌트가 활성화되어 있는지 확인합니다.

```bash
# Zuul의 각 서비스 프로세스가 정상적으로 여러 개 동작 중인지 확인
$ sudo systemctl status zuul-executor
$ sudo systemctl status zuul-merger
$ sudo systemctl status zuul-scheduler
```

---

## 권장 업그레이드 파이프라인 (Bottom-Up)

롤링 업그레이드 시 아무 컴포넌트나 먼저 껐다 켜면 안 됩니다. 구버전의 스케줄러가 신버전의 스케줄러와 소통하려면 **하위 호환성(Backwards Compatibility)**이 유지되어야 하기 때문입니다. 따라서 **말단에서 작업을 수행하는 노드부터 핵심 뇌 역할을 하는 노드 순**으로 **Bottom-up 방식**의 업그레이드를 진행해야 합니다.

![롤링 업그레이드 단계](./assets/Step%203.%20Zuul%20Scheduler.png)

### Step 1. Zuul Executor (실행기)

가장 먼저, 실제 테스트 잡을 수행하는 **실행기(Executor)**를 업그레이드합니다.  
Zuul은 **`sigterm_method=graceful`** 설정을 통해 진행 중인 작업이 끊기지 않고 끝날 때까지 대기한 후 안전하게 종료할 수 있습니다.

```bash
# 1. 실행기 종료 (기존 잡이 끝날 때까지 대기)
$ sudo systemctl stop zuul-executor

# 2. 패키지 버전 업그레이드 진행
$ pip install --upgrade zuul

# 3. 새로운 버전으로 실행기 재시작
$ sudo systemctl start zuul-executor
```

### Step 2. Zuul Merger (병합기)

Git 레포지토리의 코드를 병합하는 역할을 하는 **병합기(Merger)**를 두 번째로 업그레이드합니다.

```bash
# 병합기 서비스 중지 후 패치 및 재시작
$ sudo systemctl stop zuul-merger
$ pip install --upgrade zuul
$ sudo systemctl start zuul-merger
```

### Step 3. Zuul Scheduler (스케줄러)

말단 노드들의 업그레이드가 모두 끝났다면, 마지막으로 파이프라인과 큐(Queue) 상태를 관리하는 **스케줄러**를 재시작합니다. 이 단계에서는 **DB 마이그레이션이 수반될 수 있음**에 유의합니다.

```bash
# 스케줄러 업그레이드 및 재시작 (DB 마이그레이션이 수반될 수 있음)
$ sudo systemctl stop zuul-scheduler
$ pip install --upgrade zuul
$ sudo systemctl start zuul-scheduler
```

> **참고:** 실제 대규모 프로덕션에서는 Global Python 환경에 직접 `pip install`을 하기보다는 **가상 환경(Virtualenv)**이나 **컨테이너(Container)**를 주로 사용합니다.

---

## 오프라인 마이그레이션 (Major Upgrade)

무조건 롤링 업그레이드가 가능한 것은 아닙니다. 예를 들어, **Zuul 5.x 버전에서 7.x 버전으로 건너뛰는 것**과 같은 메이저 버전 업데이트의 경우, 아키텍처나 DB 스키마 구조가 완전히 바뀌는 **대격변**이 일어납니다. 이때는 구버전과 신버전 간의 하위 호환성 코드가 삭제되었을 확률이 매우 높습니다.

이런 상황에서는 어쩔 수 없이 **전체 컴포넌트를 완전히 끄고(Offline)** 대규모 마이그레이션을 진행해야 합니다. 서비스 중단이 발생할 수밖에 없는 상황을 정확히 인지하고, **사전에 공지 및 DB 백업 계획**을 세우는 것이 중요합니다.

### 1. 전체 중지 및 백업

```bash
# 메이저 업그레이드 시 전체 컴포넌트 동시 중지 (서비스 중단 발생)
$ sudo systemctl stop zuul-web zuul-merger zuul-executor zuul-scheduler

# 데이터베이스 스냅샷 백업 (필수)
$ pg_dump zuul_db > zuul_db_backup_pre_upgrade.sql

# ZooKeeper 상태 캐시 초기화 후 메이저 업그레이드 진행
$ zuul-admin delete-state --keep-config-cache
```

### 2. 스케줄러 기동을 통한 DB 마이그레이션

스케줄러 하나를 먼저 시작합니다. 스케줄러는 기동 시 **데이터베이스 마이그레이션을 자동으로 수행**합니다.

```bash
# 단일 스케줄러 시작
$ sudo systemctl start zuul-scheduler
```

로그를 통해 마이그레이션 완료를 확인합니다.

```bash
# 로그를 통해 마이그레이션 완료 확인
$ tail -f /var/log/zuul/scheduler.log
```

다음과 같은 로그 메시지가 출력되면 마이그레이션 및 초기화가 정상 완료된 것입니다.

```text
... "INFO zuul.Scheduler: DB Schema migration complete" ...
... "INFO zuul.Scheduler: Tenant configuration loaded" ...
```

### 3. 나머지 컴포넌트 재기동

스케줄러의 마이그레이션과 초기화가 완료되면 나머지 컴포넌트들을 **순차적으로** 올려 서비스를 정상화합니다.

```bash
$ sudo systemctl start zuul-merger
$ sudo systemctl start zuul-executor
$ sudo systemctl start zuul-web
```

---

## 결론: Zuul 분산 환경 설계의 이점

Zuul은 대규모 분산 환경을 고려하여 설계되었기 때문에, **`sigterm_method=graceful`** 설정과 **ZooKeeper**를 활용한 상태 관리를 통해 업그레이드 시의 충격을 최소화할 수 있습니다.

- **Control Plane(스케줄러, 웹, DB, ZooKeeper)**과 **Data Plane(Executor, Merger)**의 분리로, 말단 노드부터 순차 업그레이드가 가능합니다.
- **ZooKeeper**를 통한 분산 상태 공유로, 컴포넌트 간 일관된 상태를 유지하며 롤링 업그레이드를 수행할 수 있습니다.
- **SQL Database**에 빌드 기록을 저장하고, 스케줄러 기동 시 자동 DB 마이그레이션을 수행함으로써 메이저 업그레이드 시에도 절차를 명확히 할 수 있습니다.

아래는 코드 리뷰 시스템(GitHub/Gerrit)과 연동된 Zuul 전체 아키텍처를 나타낸 다이어그램입니다.

![코드 리뷰 시스템](./assets/코드%20리뷰%20시스템.png)

---

*이 문서는 오픈소스 Zuul 커뮤니티 기여를 위한 기술 정리입니다.*
