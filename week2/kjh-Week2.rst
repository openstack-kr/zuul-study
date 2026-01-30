Zuul 기초 정리
=============

이 문서는 Zuul 공식 튜토리얼을 직접 실습하며 정리한 Zuul의 핵심 개념과 전체 구조를 설명한다.

Zuul은 단일 저장소 중심의 기존의 CI와는 다른, 여러 프로젝트가 하나의 시스템으로
함께 동작하는지를 검증하기 위해 설계된 멀티 레포지토리 중심 CI 도구이다.


1. Zuul 전체 개요
-----------------

Zuul에서 코드 변경이 테스트되고 실행되는 전체 흐름은 다음과 같다::

  tenant → pipeline → project → job → nodeset
         → nodepool → inventory → playbook

각 단계는 역할이 명확히 분리되어 있으며, 이를 통해 대규모 멀티 프로젝트 CI를
안정적으로 운영할 수 있다.


2. 디렉터리 구조
----------------

2.1 Zuul 튜토리얼 인프라와 Docker
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

::

  zuul/
  └── doc/source/examples/
      ├── docker-compose.yaml
      ├── gerrit/
      ├── nodepool/
      └── zuul/

Zuul 공식 튜토리얼에서 제공하는 예제 인프라 디렉터리이다.

Docker는 Zuul 인프라를 실행하기 위한 제어 환경이다.
Docker로 실행되는 주요 컴포넌트는 다음과 같다.

- Zuul Scheduler
- Zuul Executor
- Zuul Web
- Gerrit
- Database
- Nodepool 서비스

Docker 컨테이너는 호스트 커널을 공유하므로 완전히 격리된 실행 환경을 제공하지는 못한다.

따라서 Docker는 Zuul 제어에만 사용되며,
실제 CI Job 실행 환경은 Nodepool이 제공하는 VM을 사용한다.


2.2 Zuul 설정 저장소 (zuul-config)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

::

  zuul-config/
  ├── zuul.d/
  │   ├── tenant.yaml
  │   ├── pipelines.yaml
  │   ├── jobs.yaml
  │   └── project.yaml
  └── playbooks/

``zuul-config`` 는 trusted config 저장소로, Zuul 전체의 공통 pipeline과
Job 템플릿을 정의한다.


2.3 프로젝트 저장소
~~~~~~~~~~~~~~~~~~~

::

  test1/
  ├── zuul.yaml
  ├── README.md
  └── .git/

각 프로젝트 내부에서 ``zuul.yaml`` 을 통해 자신이 사용할 pipeline과 job을 선언한다.


3. Pipeline
-----------

Pipeline은 다음을 정의한다.

- 언제 실행할 것인가 (trigger)
- 어떻게 실행할 것인가 (manager)
- 성공/실패 시 어떤 처리를 할 것인가


3.1 Pipeline Manager 종류
~~~~~~~~~~~~~~~~~~~~~~~~~

``independent``
  각 변경사항을 독립적으로 병렬 실행한다.

``dependent``
  변경사항을 누적하여 순차적으로 테스트한다.
  (A → A+B → A+B+C)
  Gate pipeline에서 필수적으로 사용된다.

``supercedent``
  최신 변경사항만 유지하며, 이전 실행 중인 job은 취소된다.

``serial``
  병렬 실행 없이 하나씩 순차 실행한다.


3.2 Pipeline.yaml 예시
~~~~~~~~~~~~~~~~~~~~~~~

::

  - pipeline:
      name: check
      manager: independent
      trigger:
        gerrit:
          - event: patchset-created
      success:
        gerrit:
          Verified: 1
      failure:
        gerrit:
          Verified: -1


4. Job과 Project
----------------

4.1 Job
~~~~~~~

Job은 pipeline과 project로부터 호출되어 실제로 실행될 playbook과 실행 규칙을 정의한다.

::

  - job:
      name: unit-test
      parent: base
      nodeset:
        nodes:
          - name: primary
            label: ubuntu-jammy
      vars:
        python_version: "3.11"
        tox_env: py311
      timeout: 3600
      run: playbooks/unit-test.yaml


4.2 Project.yaml
~~~~~~~~~~~~~~~~~

Project.yaml는 실제 프로젝트와 pipeline과 job을 연결한다.

::

  - project:
      name: test1
      check:
        jobs:
          - unit-test:
              branches: "^main$"
              files: "^src/.*"
      gate:
        jobs:
          - unit-test


5. Nodepool
-----------

Nodepool은 Job 실행을 위해 임시 VM 기반 CI 워커 노드를 제공하는 컴포넌트이다.

주요 개념은 다음과 같다.

``provider``
  노드를 실제로 생성하는 백엔드 (OpenStack, AWS 등)

``image``
  노드의 OS 및 기본 환경 이미지

``label``
  노드의 용도와 의미를 나타내는 이름

``nodeset``
  Job이 필요로 하는 노드들의 묶음

Nodepool은 Job 실행 시 항상 깨끗한 상태의 노드를 제공하여 완전히 격리된 실행 환경을 구성한다.


6. Ansible
----------

6.1 Infrastructure as Code
~~~~~~~~~~~~~~~~~~~~~~~~~~

Infrastructure as Code(IaC)는 환경의 배포와 구성을 코드로 정의하는 개념이다.


6.2 Ansible 개요
~~~~~~~~~~~~~~~~

Ansible은 에이전트리스 구성 관리 도구로, SSH를 통해 서버에 접속하여 작업을 수행한다.

- 에이전트 설치 불필요
- 멱등성(idempotence) 제공
- 이미 최종 상태에 도달했다면 작업을 수행하지 않음


6.3 Inventory
~~~~~~~~~~~~~

Inventory는 Ansible이 작업을 수행할 서버(노드) 목록을 정의한다.

Zuul에서는 다음과 같이 동작한다.

- Job이 실행되면 nodeset을 확인
- Nodepool에 노드를 요청
- 제공된 노드로 Inventory 생성
- 해당 Inventory를 사용해 playbook 실행


6.4 Playbook
~~~~~~~~~~~~

Playbook은 Inventory에 정의된 노드에서 수행할 작업을 정의한다.
Zuul pipeline, job 등을 통해 실제로 최종 수행되는 작업이다.

::

  - hosts: all
    tasks:
      - name: Run unit tests
        command: pytest -v
        args:
          chdir: "{{ zuul.project.src_dir }}"

