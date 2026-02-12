================================================
Zuul & CI/CD 개념 및 아키텍처 정리
================================================

1. CI/CD란?
===========
단순히 코드를 합치고 배포하는 것이 아니라, 소프트웨어 개발의 전 과정을 **자동화된 컨베이어 벨트** 위에 올리는 것.

* **CI (Continuous Integration):** 합칠 때마다 자동으로 빌드하고 테스트해서 이 코드가 기존 시스템을 망가뜨리지 않는지 즉시 검증함.
* **CD (Continuous Delivery/Deployment):** 이 코드를 실제 사용자 환경이나 테스트 환경으로 자동으로 전송함.

왜 필요한가?
------------
* **사전 차단:** 코드를 올릴 때마다 Zuul이 검사함. 에러가 나면 즉시 반려시켜 작은 에러를 미리 잡아 큰 불을 막음.
* **본질 집중:** CI/CD 파이프라인은 테스트 및 배포 과정을 단축시킴. 개발자는 코드 작성이라는 본질적 가치에 집중할 수 있음.
* **안전 장치:** 파이프라인 상의 테스트가 장애를 감지하고 배포를 중단시킴. 검증되지 않은 코드는 절대 서비스에 나갈 수 없음.

OpenStack 관점에서의 중요성
---------------------------
OpenStack처럼 수십 개의 프로젝트가 서로 얽혀 있는 거대 오픈소스 프로젝트에서는 CI 없이는 개발이 불가능함.
프로젝트 수정 사항이 다른 프로젝트를 깨뜨리는지 확인하기 위해 Zuul 같은 고도화된 CI 시스템이 **모든 연관 관계를 따져서 검증**하는 것임.

2. Jenkins vs Zuul 차이점
=========================

**Jenkins**
    * CI 및 자동화 도구
    * 주로 **머지 후(Post-merge)** 테스트
    * 프로젝트 간 연동이 복잡하고 어려움
    * Master-Slave 구조 (병목 발생 가능)
    * 기존 서버 재사용 (설정 꼬임 발생 가능)

**Zuul**
    * 프로젝트 게이팅(Project Gating) 시스템
    * **머지 전(Pre-merge)** 테스트
    * Cross-Project Dependency 완벽 지원
    * 무상태(Stateless) 아키텍처 (수평 확장 용이)
    * Nodepool로 매번 **깨끗한 새 환경** 생성

**결론:** OpenStack 같은 마이크로 서비스 생태계에서는 상호 의존성 검증과 무결성 보장에 특화된 Zuul이 필수임.

3. 오픈소스 발전과 인프라
=======================
OpenStack은 데이터센터의 서버, 스토리지, 네트워크 장비를 소프트웨어로 제어하는 거대한 운영체제(오픈소스 AWS)임.

* **Nova:** 가상머신 생성
* **Neutron:** 가상 네트워크 생성
* **Swift/Cinder:** 데이터 저장
* **Keystone:** 로그인 및 인증 담당

**Nodepool의 역할:**
Nodepool은 작업장(Node)을 생성함. Zuul은 OpenStack의 복잡한 개발을 자동화하기 위해 탄생했으며, Nodepool을 통해 OpenStack의 자원을 할당받아 테스트 환경을 동적으로 구축함.

4. Job 실행의 핵심: Ansible과 Nodepool
======================================
Zuul은 직접 명령어를 실행하지 않음. 실제 실행은 **Ansible**과 **Nodepool**이 담당함.

Ansible
-------
* 서버에 접속해서 명령어를 수행하는 자동화 도구 (Agentless, SSH만 있으면 됨).
* Zuul이 Nodepool에게 받은 서버 정보로 **인벤토리(서버 주소록)**를 작성함.
* ``ansible-playbook`` 명령어로 작성된 YAML을 실행함.
* 따라서 Custom Job을 만들려면 쉘 스크립트가 아니라 Ansible 문법을 배워야 함.

Nodepool & Docker
-----------------
* Nodepool은 자원을 관리함.
* 로컬 환경에서는 무거운 OpenStack VM 대신 **Docker 컨테이너**를 VM인 척 속여서 띄움.
* **흐름:** Zuul 요청 -> Nodepool Launcher -> Docker Daemon -> Container 생성(SSH 키 주입) -> Zuul에게 IP 전달

5. Sample Job의 동작 아키텍처 분석
==================================

1. **이벤트 감지 (Gerrit -> Zuul Scheduler)**
    * 코드를 업로드하면 Gerrit이 Zuul에게 새 이벤트 발생 신호를 보냄.

2. **계획 수립 (Zuul Scheduler)**
    * YAML 설정을 읽고 어떤 Job을 수행할지 파악함.

3. **자원 할당 (Zuul Scheduler -> Nodepool -> Docker)**
    * Zuul이 자원을 요청하면, Nodepool이 Docker에게 명령해 새 컨테이너를 띄우고 정보를 Zuul에게 전달함.

4. **실행 (Zuul Executor -> Ansible -> Test Node)**
    * Zuul Executor가 받은 IP로 Ansible Inventory를 만듦.
    * ``job.yaml``을 실행함 (Ansible이 SSH로 컨테이너에 접속해 코드 수행).
    * 성공/실패 결과를 반환함.

5. **결과 보고 (Zuul Scheduler -> Gerrit)**
    * Zuul이 Gerrit에 접속(SSH)하여 해당 Change에 댓글(Verified +1)을 남김.

**요약:** Zuul은 Gerrit(코드), Nodepool(인프라), Ansible(실행) 3박자를 조율하는 엔진임.
