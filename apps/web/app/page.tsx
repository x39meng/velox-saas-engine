import { checkSystemStatus } from "./actions/auth";
import { signupAction } from "./actions";

export default async function Home() {
  const status = await checkSystemStatus();
  return (
    <div className="flex min-h-screen flex-col items-center justify-center p-24">
      <h1 className="text-4xl font-bold mb-8">Velox SaaS Engine</h1>
      <pre className="bg-gray-100 p-4 rounded mb-8">{JSON.stringify(status, null, 2)}</pre>
      <form action={signupAction} className="flex flex-col gap-4 w-full max-w-md">
        <input
          name="email"
          type="email"
          placeholder="Email"
          required
          className="p-2 border rounded"
        />
        <input
          name="name"
          type="text"
          placeholder="Name"
          className="p-2 border rounded"
        />
        <button
          type="submit"
          className="bg-black text-white p-2 rounded hover:bg-gray-800"
        >
          Sign Up
        </button>
      </form>
    </div>
  );
}
