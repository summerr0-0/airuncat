# Vector Cat, No Image Assets

고양이는 코드로 그리는 벡터 드로잉이다. 외부 PNG/스프라이트 에셋을 추가하지 마라.

- 각 프레임은 `phase` 값을 받아 NSBezierPath로 매번 렌더한다 (몸/머리/귀/꼬리/다리).
- 애니메이션 = phase 증가, 속도 = 활성 세션 수 (`SessionStore.tick()`).
- 새 포즈가 필요하면 `CatMode`에 케이스를 추가하고 `CatRenderer`에 대응 그리기 함수를 더한다.
- 변경 후 `/render-cat`으로 프레임 PNG를 뽑아 눈으로 확인한다.
