import { greeting } from "@/lib/greeting";

export default function Home() {
  return (
    <main className="container">
      <h1>{greeting("世界")}</h1>
      <p>このアプリは ai-dev-template から作られました。docs/spec.md に仕様を書いて始めます。</p>
    </main>
  );
}
