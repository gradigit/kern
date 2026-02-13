import { test, expect, Page } from "@playwright/test";

/**
 * Helper: set editor markdown content via the window.kern bridge,
 * then wait for mermaid to finish rendering.
 */
async function setMermaidContent(page: Page, mermaidCode: string) {
  const md = "# Test\n\n```mermaid\n" + mermaidCode + "\n```\n";
  await page.evaluate(
    (content) => (window as any).kern.setMarkdown(content),
    md,
  );
  // Wait for mermaid async render — look for the SVG or error element
  await page.waitForFunction(
    () => {
      const c = document.querySelector(".mermaid-container svg");
      const e = document.querySelector(".mermaid-error");
      return c || e;
    },
    { timeout: 15_000 },
  );
}

test.describe("Mermaid Diagrams", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
    await page.waitForSelector(".milkdown .editor", { timeout: 10_000 });
  });

  test("default sample flowchart renders SVG with text labels", async ({
    page,
  }) => {
    // The default SAMPLE_MARKDOWN has a flowchart
    const svg = page.locator(".mermaid-container svg");
    await expect(svg.first()).toBeVisible({ timeout: 15_000 });
    // Should have foreignObject elements (htmlLabels mode)
    const foreignObjects = svg.first().locator("foreignObject");
    expect(await foreignObjects.count()).toBeGreaterThan(0);
  });

  test("flowchart with subgraphs renders all nodes", async ({ page }) => {
    await setMermaidContent(
      page,
      `flowchart TD
    A([Start]) --> B{Valid?}
    B -->|Yes| C[Process]
    B -->|No| D[Error]
    subgraph Sub[Pipeline]
        direction TB
        S1[Step 1] --> S2[Step 2]
    end
    C --> Sub
    Sub --> E([End])`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    // Flowcharts use foreignObject for labels
    const fo = svg.locator("foreignObject");
    expect(await fo.count()).toBeGreaterThan(0);
    // Check text content is present
    const text = await svg.textContent();
    expect(text).toContain("Start");
    expect(text).toContain("Pipeline");
    expect(text).toContain("Step 1");
  });

  test("sequenceDiagram renders participants and messages", async ({
    page,
  }) => {
    await setMermaidContent(
      page,
      `sequenceDiagram
    participant A as Alice
    participant B as Bob
    A->>B: Hello Bob
    B-->>A: Hi Alice
    alt Happy
        A->>B: Great!
    else Sad
        A->>B: Oh no
    end`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Alice");
    expect(text).toContain("Bob");
    expect(text).toContain("Hello Bob");
  });

  test("classDiagram renders classes with methods", async ({ page }) => {
    await setMermaidContent(
      page,
      `classDiagram
    class Animal {
        +String name
        +int age
        +makeSound() void
    }
    class Dog {
        +fetch() void
    }
    Animal <|-- Dog`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Animal");
    expect(text).toContain("Dog");
    expect(text).toContain("name");
  });

  test("stateDiagram-v2 renders nested states", async ({ page }) => {
    await setMermaidContent(
      page,
      `stateDiagram-v2
    [*] --> Idle
    state Idle {
        [*] --> Waiting
        Waiting --> Active: start
    }
    Idle --> Running: go
    Running --> [*]`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Idle");
    expect(text).toContain("Waiting");
    expect(text).toContain("Running");
  });

  test("erDiagram renders entities and relationships", async ({ page }) => {
    await setMermaidContent(
      page,
      `erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ ITEM : contains
    USER {
        uuid id PK
        string name
    }
    ORDER {
        uuid id PK
        date created
    }`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("USER");
    expect(text).toContain("ORDER");
    expect(text).toContain("places");
  });

  test("gantt chart renders tasks and dates", async ({ page }) => {
    await setMermaidContent(
      page,
      `gantt
    title Project
    dateFormat YYYY-MM-DD
    section Build
    Task A :done, a1, 2025-01-01, 7d
    Task B :active, a2, after a1, 5d`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Task A");
    expect(text).toContain("Task B");
    expect(text).toContain("Project");
  });

  test("pie chart renders slices with labels", async ({ page }) => {
    await setMermaidContent(
      page,
      `pie title Languages
    "Swift" : 45
    "TypeScript" : 25
    "CSS" : 15
    "Other" : 15`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Swift");
    expect(text).toContain("TypeScript");
    expect(text).toContain("Languages");
  });

  test("gitGraph renders commits and branches", async ({ page }) => {
    await setMermaidContent(
      page,
      `gitGraph
    commit id: "init"
    commit id: "feat-1"
    branch develop
    commit id: "dev-1"
    checkout main
    merge develop
    commit id: "release"`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("init");
    expect(text).toContain("release");
  });

  test("mindmap renders nodes", async ({ page }) => {
    await setMermaidContent(
      page,
      `mindmap
  root((Project))
    Frontend
      React
      CSS
    Backend
      Node
      DB`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Project");
    expect(text).toContain("Frontend");
    expect(text).toContain("Backend");
  });

  test("timeline renders events", async ({ page }) => {
    await setMermaidContent(
      page,
      `timeline
    title Timeline
    2025-01 : Started
             : Designed
    2025-02 : Built
             : Shipped`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Started");
    expect(text).toContain("Shipped");
    expect(text).toContain("Timeline");
  });

  test("journey diagram renders activities", async ({ page }) => {
    await setMermaidContent(
      page,
      `journey
    title User Flow
    section Login
      Open app: 5: User
      Enter creds: 3: User
    section Use
      View data: 5: User`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("User Flow");
    expect(text).toContain("Open app");
    expect(text).toContain("Login");
  });

  test("sankey-beta diagram renders flows", async ({ page }) => {
    await setMermaidContent(
      page,
      `sankey-beta

Source A,Target X,30
Source A,Target Y,20
Source B,Target X,15
Source B,Target Y,25`,
    );
    const svg = page.locator(".mermaid-container svg");
    await expect(svg).toBeVisible();
    const text = await svg.textContent();
    expect(text).toContain("Source A");
    expect(text).toContain("Target X");
  });

  test("invalid mermaid shows error", async ({ page }) => {
    const md = "# Test\n\n```mermaid\nthis is not valid mermaid syntax!!!\n```\n";
    await page.evaluate(
      (content) => (window as any).kern.setMarkdown(content),
      md,
    );
    // Wait for error element to appear
    const error = page.locator(".mermaid-error");
    await expect(error).toBeVisible({ timeout: 15_000 });
    const text = await error.textContent();
    expect(text).toContain("Mermaid error");
  });

  test("multiple mermaid blocks render independently", async ({ page }) => {
    const md = `# Multi

\`\`\`mermaid
pie title First
    "A" : 60
    "B" : 40
\`\`\`

## Second

\`\`\`mermaid
flowchart LR
    X --> Y --> Z
\`\`\`
`;
    await page.evaluate(
      (content) => (window as any).kern.setMarkdown(content),
      md,
    );
    // Wait for both to render
    await page.waitForFunction(
      () => document.querySelectorAll(".mermaid-container svg").length >= 2,
      { timeout: 15_000 },
    );
    const containers = page.locator(".mermaid-container svg");
    expect(await containers.count()).toBe(2);
  });
});
