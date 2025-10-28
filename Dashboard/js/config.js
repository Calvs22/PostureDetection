// Supabase configuration
const SUPABASE_URL = "https://brgabqwalqhsedehkhlr.supabase.co"; // 🔹 Replace this
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJyZ2FicXdhbHFoc2VkZWhraGxyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MDg2MDczMiwiZXhwIjoyMDc2NDM2NzMyfQ.LbPqicNxR6AY2l_YQ5YLS_e8Vti8RkeMpaCodXRuoCg"; // 🔹 Replace this

// Initialize Supabase
const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

// Log configuration for debugging
console.log('Supabase URL:', SUPABASE_URL);
console.log('Supabase Key:', SUPABASE_KEY ? 'Key is set' : 'Key is missing');