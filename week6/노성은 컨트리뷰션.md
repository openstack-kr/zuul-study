노성은 작성

## Zuul 문서 빌드 시스템 분석
### : Sphinx와 i18n의 동작 메커니즘
  
최근 Zuul 스터디의 한글화 기여를 시작하면서, 단순히 문장을 번역하는 것을 넘어 "이 번역이 시스템 내부에서 어떻게 처리되고
 변환되는가?"에 대한 궁금증이 생겼습니다. 이에, 본 글에서는 zuul 문서가 Sphinx와 국제화(i18n) 프로세스를 거쳐 다국어 HTML로 빌드되는
내부 아키텍처와 데이터 흐름을 분석해 보고자 합니다.

&nbsp;
&nbsp;

## Sphinx와 i18n
### 1. Sphpinx (스핑크스)
Sphinx는 파이썬 커뮤니티에서 가장 많이 쓰이는 문서 생성 도구입니다.  
작성한 파일을 읽어서 우리가 브라우저로 보는 정돈된 웹사이트(HTML)로 만들어줍니다.
- **주요 기능**
    - 다양한 출력 포맷 지원: HTML, LaTeX (PDF), ePub, Texinfo, 매뉴얼 페이지 등 다양한 형식으로 문서를 출력할 수 있습니다.
    - 자동 문서 생성: Python 코드에서 주석을 추출하여 자동으로 문서를 생성할 수 있습니다.
    - 국제화 지원
    - 확장 가능, 테마와 플러그인 지원

Sphinx를 살펴보며 알게 된 가장 중요한 개념은 **Builder** 패턴입니다.  
우리가 터미널에 입력하는 명령어에 따라, Sphinx 다양한 결과물을 만들어냅니다.

- **`make html`** → **HTML Builder** 호출
    - RST 파일을 파싱하여 웹 브라우저용 정적 사이트(Static Site)를 생성합니다.
- **`make gettext`** → **Gettext Builder** 호출
    - RST 파일에서 텍스트만 추출하여 `.pot` 템플릿 파일을 생성합니다.
- **`make latexpdf`** → **LaTeX Builder** 호출
    - 인쇄 가능한 고품질 PDF 파일을 생성합니다.

즉, "소스(RST)는 하나지만, 빌더(Builder)에 따라 결과물은 무한하다"는 것이 Sphinx 아키텍처의 핵심입니다.

&nbsp;

### 2.  i18n (Internationalization, 국제화)
**i18n**은 소프트웨어나 문서가 다양한 언어와 지역에 맞게 표시될 수 있도록 **설계하는 과정** 자체를 의미합니다.  
(어떤 언어든 들어올 수 있는 빈 자리를 만들어두는 기술적인 설계라고 할 수 있습니다..)

- **역할:** 문서 시스템이 "이 문장은 한국어로, 저 문장은 영어로" 보여줄 수 있는 **틀**을 제공합니다.
- **핵심 도구 (gettext):** 현재 저희가 진행 중인 Zuul 번역 프로젝트는, i18n을 구현하기 위해 `gettext`라는 표준 도구를 사용합니다.
    - **`.pot` 파일:** 문서에서 번역이 필요한 텍스트만 뽑아낸 '틀' (Template)
    - **`.po` 파일:** 그 틀에 한국어 내용을 채워 넣은 '실제 번역본' (Portable Object)

&nbsp;
&nbsp;
  
## 데이터 처리 파이프라인 (RST ⇒ HTML)
실제 pot 파일을 통해 번역을 진행하며, 가장 흥미로웠던 점은 “RST 파일이 어떤 과정을 거쳐 한글 HTML로 변환되는가” 였습니다.  
(번역된 po 파일을 빌드하면, 웹 페이지에 번역한 부분이  한글로 바로 반영된다는 점이 아주 흥미로웠습니다.)

이 과정은 크게 3단계의 데이터 변환 흐름을 가집니다.
### **1. 추출 (Extraction): RST → POT**

: 빌드 시스템(예: `make gettext`)은 소스 디렉터리(`doc/source`)의 모든 RST 파일을 스캔하여 번역 대상 문자열을 추출합니다. (Sphinx가 문서의 모든 영문 텍스트를 긁어 모읍니다.) 

이 결과물은 **POT (Portable Object Template)** 파일로 생성됩니다. 이 파일은 번역의 '뼈대' 역할을 합니다.

### **2. 번역 (Translation): POT → PO**

: POT 템플릿을 기반으로 각 언어별 **PO (Portable Object)** 파일이 생성됩니다. 우리는 이 파일을 가지고, Weblate나 에디터에서 실제로 작업하게 됩니다.

- *위치:* `doc/source/locale/ko/LC_MESSAGES/`

### **3. 컴파일 및 렌더링 (Compilation): PO → MO → HTML**

: Sphinx는 텍스트 파일인 `.po`를 직접 읽지 않고, 다음과 같은  **빌드 파이프라인**을 거칩니다.

1) **바이너리 컴파일 (MO 생성):**
    - 빌드 시(`make html`), `msgfmt` 도구가 `.po` 파일을 기계가 읽기 쉬운 바이너리 포맷인 **MO (Machine Object)** 파일로 컴파일합니다.
    - Sphinx는 이 MO 파일을 메모리에 로드하여 해시 테이블(Hash Table) 구조로 빠르게 조회를 수행합니다.
2) **파싱 (Parsing) 및 변환 (Transform):**
    - Sphinx는 원본 `.rst` 파일을 읽어 **Doctree(Document Tree)**라고 불리는 구조화된 데이터(DOM 유사 객체)로 메모리에 적재합니다.
    - 이때 `conf.py` 설정과 메모리에 로드된 **MO 데이터(번역)**를 결합하여, 원본 영문 텍스트를 한글로 매핑(Mapping)합니다.
3) **렌더링 (Rendering):**
    - 최종적으로 완성된 Doctree를 선택된 빌더(HTML 등)가 실제 파일로 출력(Write)하여 웹페이지를 생성합니다.

  <img width="1101" height="902" alt="image" src="https://github.com/user-attachments/assets/54ed0f81-0e44-4800-afdc-78063abb0767" />

&nbsp;
  
### 프로젝트 구조
> 실제 프로젝트 내에서는 다음과 같은 디렉토리 구조 위에서 작동합니다.
> 

** 핵심 구조만 표시하였습니다.
<img width="631" height="350" alt="image" src="https://github.com/user-attachments/assets/905450a6-0d19-4550-a424-0cde9f533002" />
- source 디렉토리는 Sphinx가 읽어들이는 핵심 작업 공간으로, 실제 작성한 코드입니다.
- build는 html, css, js(빌드된 파)로 변환된 파일이 저장되는 공간입니다.

&nbsp;
  
## 로컬 빌드를 통한 검증 단계
### 1. 환경 구성
<img width="621" height="317" alt="image" src="https://github.com/user-attachments/assets/e7c18118-c6de-4672-8994-3e2a2e975e68" />

&nbsp;

### 2. 번역 파일 구조 설정 (ko_KR 폴더 생성)
: 번역 파일(.po)이 표준 구조에 맞게 배치되어야 Sphinx 빌드 도구가 한국어를 인식합니다.
<img width="624" height="97" alt="image" src="https://github.com/user-attachments/assets/ec3dbbf3-2036-4050-882e-98438c9f11d3" />

&nbsp;

### 3. 로컬 빌드 실행 (HTML 생성)
작성 번역 내용을 바탕으로 실제 웹 페이지 형태의 HTML 파일을 생성합니다.
<img width="607" height="117" alt="image" src="https://github.com/user-attachments/assets/60ecf1bd-dad9-4b0e-ac7b-ee2366c7faf6" />
