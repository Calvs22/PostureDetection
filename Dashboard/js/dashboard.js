// DOM Elements
const errorMessage = document.getElementById('errorMessage');
const totalUsersEl = document.getElementById('totalUsers');
const totalWorkoutsEl = document.getElementById('totalWorkouts');
const totalExercisesEl = document.getElementById('totalExercises');
const avgPerformanceEl = document.getElementById('avgPerformance');
// UPDATED: Use the new ID for the stat card
const atRiskUsersCountEl = document.getElementById('atRiskUsersCount');
const applyFiltersBtn = document.getElementById('applyFilters');
const exportBtn = document.getElementById('exportData');
const dateRangeSelect = document.getElementById('dateRange');
const minAgeInput = document.getElementById('minAge');
const maxAgeInput = document.getElementById('maxAge');
const genderFilterSelect = document.getElementById('genderFilter');
const currentDateTimeEl = document.getElementById('currentDateTime');

// Connection Test Elements
const testConnectionBtn = document.getElementById('testConnection');
const connectionStatus = document.getElementById('connectionStatus');
const statusUrl = document.getElementById('statusUrl');
const statusKey = document.getElementById('statusKey');
const statusConnection = document.getElementById('statusConnection');
const statusProfiles = document.getElementById('statusProfiles');
const statusPerformance = document.getElementById('statusPerformance');

// Chart instances
// Removed 'trendChart'
let genderChart, ageChart, goalChart, exerciseChart, durationChart, accuracyChart, riskChart;

// Mock data flag
const USE_MOCK_DATA = false; // Set to false when database is ready

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
    // Check admin session first
    if (!checkAdminSession()) {
        return;
    }

    updateDateTime();
    setInterval(updateDateTime, 60000);

    // Set up event listeners
    applyFiltersBtn.addEventListener('click', loadDashboardData);
    exportBtn.addEventListener('click', exportData);
    testConnectionBtn.addEventListener('click', testSupabaseConnection);

    // Add logout button listener
    const logoutBtn = document.getElementById('logoutBtn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', logout);
    }

    // Initial load
    loadDashboardData();
});

// Update current date and time
function updateDateTime() {
    const now = new Date();
    const options = {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    };
    currentDateTimeEl.textContent = now.toLocaleDateString('en-US', options);
}

// Show error message
function showError(message) {
    errorMessage.textContent = message;
    errorMessage.style.display = 'block';
}

// Hide error message
function hideError() {
    errorMessage.style.display = 'none';
}

// Test Supabase connection
async function testSupabaseConnection() {
    // Helper function to set status
    const setStatus = (el, content, type) => {
        el.textContent = content;
        el.className = `status-value ${type}`; // 'loading', 'success', or 'error'
    };

    try {
        // Show connection status panel
        connectionStatus.style.display = 'block';

        // Reset and show initial checking status
        setStatus(statusUrl, 'Checking...', 'loading');
        setStatus(statusKey, 'Checking...', 'loading');
        setStatus(statusConnection, 'Testing...', 'loading');
        setStatus(statusProfiles, 'Testing...', 'loading');
        setStatus(statusPerformance, 'Testing...', 'loading');

        // --- 1. Check client initialization ---
        if (!supabase) {
            throw new Error('Supabase client not initialized (missing config.js or global variable)');
        }

        // --- 2. Check URL and Key configuration ---
        setStatus(statusUrl, SUPABASE_URL || 'Not configured', SUPABASE_URL ? 'success' : 'error');
        setStatus(statusKey, SUPABASE_KEY ? 'Configured' : 'Not configured', SUPABASE_KEY ? 'success' : 'error');

        // --- 3. Test basic connection (Any table query) ---
        setStatus(statusConnection, 'Pinging database...', 'loading');
        const { error: pingError } = await supabase.from('profiles').select('id', { limit: 1, count: 'exact' });

        if (pingError) {
            setStatus(statusConnection, `Failed: ${pingError.message}`, 'error');
            throw new Error(`Basic connection failed: ${pingError.message}`);
        }
        setStatus(statusConnection, 'Connected', 'success');

        // --- 4. Test profiles table query ---
        setStatus(statusProfiles, 'Checking table...', 'loading');
        const { count: profilesCount, error: profilesError } = await supabase.from('profiles').select('*', { count: 'exact', head: true });

        if (profilesError) {
            // Display the specific database error
            setStatus(statusProfiles, `Error: ${profilesError.message}`, 'error');
        } else {
            // Display the success count
            setStatus(statusProfiles, `OK (${profilesCount || 0} records found)`, 'success');
        }

        // --- 5. Test session_performance table query ---
        setStatus(statusPerformance, 'Checking table...', 'loading');
        const { count: performanceCount, error: performanceError } = await supabase.from('session_performance').select('*', { count: 'exact', head: true });

        if (performanceError) {
            // Display the specific database error
            setStatus(statusPerformance, `Error: ${performanceError.message}`, 'error');
        } else {
            // Display the success count
            setStatus(statusPerformance, `OK (${performanceCount || 0} records found)`, 'success');
        }

        // Final success alert only if basic connection passed
        if (!pingError) {
            setTimeout(() => {
                alert('✅ Supabase connection test completed successfully!');
            }, 500);
        }

    } catch (error) {
        console.error('Connection test failed:', error);

        // Update main connection status with the general failure reason
        if (statusConnection.textContent.includes('Pinging database...')) {
            setStatus(statusConnection, `Failed: ${error.message}`, 'error');
        }

        // Show error message (using the original logic)
        setTimeout(() => {
            alert(`❌ Connection test failed: ${error.message}`);
        }, 500);
    }
}

// Admin session check
// In dashboard.js
function checkAdminSession() {
    const sessionData = localStorage.getItem('adminSession');

    if (!sessionData) {
        console.log('No admin session found, redirecting to login...');
        window.location.href = 'admin-login.html';  // Make sure this points to your login page
        return false;
    }

    try {
        const session = JSON.parse(sessionData);

        // Validate session structure
        if (!session.id || !session.username || !session.loginTime) {
            console.error('Invalid session structure:', session);
            localStorage.removeItem('adminSession');
            window.location.href = 'admin-login.html';  // Make sure this points to your login page
            return false;
        }

        // Check if session is older than 24 hours
        const loginTime = new Date(session.loginTime);
        const now = new Date();
        const hoursSinceLogin = (now - loginTime) / (1000 * 60 * 60);

        if (hoursSinceLogin > 24) {
            console.log('Session expired, redirecting to login...');
            localStorage.removeItem('adminSession');
            window.location.href = 'admin-login.html';  // Make sure this points to your login page
            return false;
        }

        console.log('Admin session valid for user:', session.username);
        return true;
    } catch (error) {
        console.error('Session check failed:', error);
        localStorage.removeItem('adminSession');
        window.location.href = 'admin-login.html';  // Make sure this points to your login page
        return false;
    }
}

// Add logout function
function logout() {
    localStorage.removeItem('adminSession');
    window.location.href = 'index.html';
}

// Generate mock data
function generateMockData() {
    // Generate mock profiles with your schema
    const profiles = [];
    const names = ['John Smith', 'Emma Johnson', 'Michael Brown', 'Sarah Davis', 'James Wilson',
        'Olivia Martinez', 'David Anderson', 'Sophia Taylor', 'Robert Thomas', 'Isabella Jackson',
        'William White', 'Mia Harris', 'Richard Martin', 'Charlotte Thompson', 'Joseph Garcia',
        'Amelia Rodriguez', 'Thomas Lewis', 'Harper Lee', 'Charles Walker', 'Evelyn Hall',
        'Christopher Allen', 'Abigail Young', 'Daniel Hernandez', 'Emily King', 'Matthew Wright',
        'Elizabeth Scott', 'Anthony Green', 'Ava Baker', 'Mark Adams', 'Mia Nelson',
        'Donald Hill', 'Sofia Ramirez', 'Steven Campbell', 'Avery Mitchell', 'Paul Roberts',
        'Madison Carter', 'Andrew Phillips', 'Evan Evans', 'Victoria Turner', 'Joshua Parker',
        'Lily Collins', 'Kevin Edwards', 'Zoe Stewart', 'Brian Flores', 'Chloe Morris',
        'George Nguyen', 'Grace Murphy', 'Ronald Rivera', 'Aria Cook', 'Edward Morgan'];

    for (let i = 0; i < 50; i++) {
        const gender = Math.random() > 0.5 ? 'male' : 'female';
        const birthYear = 1970 + Math.floor(Math.random() * 40);
        const birthMonth = Math.floor(Math.random() * 12) + 1;
        const birthDay = Math.floor(Math.random() * 28) + 1;

        profiles.push({
            id: `00000000-0000-0000-0000-${String(i).padStart(12, '0')}`, // Mock UUID format
            nickname: names[i],
            gender: gender,
            birthday: `${birthYear}-${birthMonth.toString().padStart(2, '0')}-${birthDay.toString().padStart(2, '0')}`,
            height: 150 + Math.random() * 50, // Random height between 150-200cm
            weight: 50 + Math.random() * 50,   // Random weight between 50-100kg
            weekly_goal: Math.floor(Math.random() * 7) + 1,
            updated_at: new Date().toISOString(),
            last_modified_at: new Date().toISOString()
        });
    }

    // Generate mock session performance data (this will replace workout sessions)
    const exercises = ['Push-ups', 'Squats', 'Lunges', 'Plank', 'Burpees', 'Jumping Jacks',
        'Sit-ups', 'Mountain Climbers', 'Deadlifts', 'Bench Press',
        'Pull-ups', 'Shoulder Press', 'Bicep Curls', 'Tricep Dips', 'Leg Press'];
    const performances = [];
    let performanceId = 1;

    // Generate sessions from performance data
    const sessions = [];
    const today = new Date();

    // Create 150 unique sessions (based on unique date+user combinations)
    for (let i = 0; i < 150; i++) {
        const daysAgo = Math.floor(Math.random() * 90);
        const date = new Date(today);
        date.setDate(date.getDate() - daysAgo);
        const dateStr = date.toISOString().split('T')[0];
        const userId = `00000000-0000-0000-0000-${String(Math.floor(Math.random() * 50)).padStart(12, '0')}`;

        sessions.push({
            id: i + 1,
            date: dateStr,
            duration_in_minutes: Math.floor(Math.random() * 60) + 15,
            user_id: userId,
            session_local_id: i + 1
        });

        // Add performance data for this session
        const sessionExercises = Math.floor(Math.random() * 5) + 3; // 3-7 exercises per session

        for (let ex = 0; ex < sessionExercises; ex++) {
            const exerciseName = exercises[Math.floor(Math.random() * exercises.length)];
            const plannedReps = Math.floor(Math.random() * 15) + 5; // 5-20 reps
            const repsCompleted = Math.floor(plannedReps * (0.5 + Math.random() * 0.5)); // 50%-100% completion
            const plannedSets = Math.floor(Math.random() * 3) + 1; // 1-3 sets

            performances.push({
                id: performanceId++,
                created_at: new Date().toISOString(),
                user_id: userId,
                session_local_id: i + 1,
                date: dateStr,
                exercise_name: exerciseName,
                reps_completed: repsCompleted,
                planned_reps: plannedReps,
                planned_sets: plannedSets
            });
        }
    }

    return { profiles, sessions, performances };
}

// Update dashboard with mock data
function updateDashboardWithMockData(data) {
    // Update stats cards
    totalUsersEl.textContent = data.profiles.length;

    // Calculate unique sessions (unique date+user combinations)
    const uniqueSessions = new Set(data.performances.map(p => `${p.user_id}-${p.date}`));
    totalWorkoutsEl.textContent = uniqueSessions.size;

    // Get unique exercises
    const uniqueExercises = [...new Set(data.performances.map(p => p.exercise_name))];
    totalExercisesEl.textContent = uniqueExercises.length;

    // Calculate average performance (accuracy)
    const validPerformances = data.performances.filter(p => p.planned_reps > 0);
    const avgAccuracy = validPerformances.length > 0
        ? (validPerformances.reduce((sum, p) => sum + (p.reps_completed / p.planned_reps), 0) / validPerformances.length * 100).toFixed(1)
        : 0;
    avgPerformanceEl.textContent = `${avgAccuracy}%`;

    // Render charts
    renderGenderChart(data.profiles);
    renderAgeChart(data.profiles);
    renderGoalChart(data.profiles);
    renderExerciseChart(data.performances);
    // Removed: renderTrendChart(data.performances);
    renderDurationChart(data.performances);
    renderAccuracyChart(data.performances);
    renderRiskChart(data.performances);
    renderUsersProgressTable(data.profiles, data.performances, data.sessions); // Keep the table update

    // Hide loading overlays
    document.querySelectorAll('.chart-loading').forEach(overlay => {
        overlay.style.display = 'none';
    });
}

// Load dashboard data
async function loadDashboardData() {
    try {
        hideError();

        // Show loading state - show overlay instead of replacing content
        document.querySelectorAll('.chart-loading').forEach(overlay => {
            overlay.style.display = 'flex';
        });

        // Use mock data if flag is set
        if (USE_MOCK_DATA) {
            // Add a small delay to show loading animation
            setTimeout(() => {
                const mockData = generateMockData();
                updateDashboardWithMockData(mockData);
            }, 500);
            return;
        }

        // Get filter values
        const dateRange = dateRangeSelect.value;
        const minAge = minAgeInput.value ? parseInt(minAgeInput.value) : null;
        const maxAge = maxAgeInput.value ? parseInt(maxAgeInput.value) : null;
        const genderFilter = genderFilterSelect.value !== 'all' ? genderFilterSelect.value : null;

        // Calculate date filter
        let dateFilter = {};
        if (dateRange !== 'all') {
            const days = parseInt(dateRange);
            const startDate = new Date();
            startDate.setDate(startDate.getDate() - days);
            dateFilter = { gte: startDate.toISOString() };
        }

        // Fetch profile data with filters
        console.log('Fetching profiles...');
        let profilesQuery = supabase.from('profiles').select('*');

        if (minAge || maxAge || genderFilter) {
            // We'll need to create a custom function for filtering by age since birthday is text
            // For now, we'll fetch all profiles and filter in JavaScript
            const { data: profiles, error: profileError } = await profilesQuery;

            if (profileError) {
                throw new Error(profileError.message);
            }

            // Filter profiles in JavaScript
            const filteredProfiles = profiles.filter(profile => {
                // Filter by gender
                if (genderFilter && profile.gender?.toLowerCase() !== genderFilter) {
                    return false;
                }

                // Filter by age
                if (minAge || maxAge) {
                    if (!profile.birthday) return false;

                    try {
                        const birthDate = new Date(profile.birthday);
                        const today = new Date();
                        let age = today.getFullYear() - birthDate.getFullYear();
                        const monthDiff = today.getMonth() - birthDate.getMonth();

                        if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
                            age--;
                        }

                        if (minAge && age < minAge) return false;
                        if (maxAge && age > maxAge) return false;
                    } catch (e) {
                        console.error('Error parsing birthday:', profile.birthday, e);
                        return false;
                    }
                }

                return true;
            });

            var profilesData = filteredProfiles;
        } else {
            const { data: profiles, error: profileError } = await profilesQuery;

            if (profileError) {
                throw new Error(profileError.message);
            }

            var profilesData = profiles;
        }

        // Fetch session performance data with date filter
        console.log('Fetching session performance...');
        let performanceQuery = supabase.from('session_performance').select('*');
        if (dateRange !== 'all') {
            performanceQuery = performanceQuery.gte('date', dateFilter.gte);
        }
        const { data: performances, error: performanceError } = await performanceQuery;

        if (performanceError) {
            throw new Error(performanceError.message);
        }

        // Derive sessions from performance data
        console.log('Deriving sessions from performance data...');
        const sessions = deriveSessionsFromPerformance(performances);

        console.log('Successfully fetched data from Supabase');
        console.log('Profiles count:', profilesData?.length);
        console.log('Sessions count:', sessions?.length);
        console.log('Performances count:', performances?.length);

        // Update stats cards
        totalUsersEl.textContent = profilesData.length;
        totalWorkoutsEl.textContent = sessions.length;

        // Get unique exercises
        const uniqueExercises = [...new Set(performances.map(p => p.exercise_name))];
        totalExercisesEl.textContent = uniqueExercises.length;

        // Calculate average performance (accuracy)
        const validPerformances = performances.filter(p => p.planned_reps > 0);
        const avgAccuracy = validPerformances.length > 0
            ? (validPerformances.reduce((sum, p) => sum + (p.reps_completed / p.planned_reps), 0) / validPerformances.length * 100).toFixed(1)
            : 0;
        avgPerformanceEl.textContent = `${avgAccuracy}%`;

        // Render charts
        renderGenderChart(profilesData);
        renderAgeChart(profilesData);
        renderGoalChart(profilesData);
        renderExerciseChart(performances);
        // Removed: renderTrendChart(sessions);
        renderDurationChart(sessions);
        renderAccuracyChart(performances);
        renderRiskChart(performances);
        renderUsersProgressTable(profilesData, performances, sessions);

        // Hide loading overlays
        document.querySelectorAll('.chart-loading').forEach(overlay => {
            overlay.style.display = 'none';
        });

    } catch (error) {
        console.error('Error loading dashboard data:', error);

        // Fall back to mock data if there's an error
        if (USE_MOCK_DATA) {
            const mockData = generateMockData();
            updateDashboardWithMockData(mockData);
        } else {
            showError(`Failed to load dashboard data: ${error.message}`);
            // Hide loading overlays on error
            document.querySelectorAll('.chart-loading').forEach(overlay => {
                overlay.style.display = 'none';
            });
        }
    }
}

// Derive sessions from performance data
function deriveSessionsFromPerformance(performances) {
    // Create a map of unique sessions (user_id + date)
    const sessionMap = new Map();

    performances.forEach(perf => {
        const sessionKey = `${perf.user_id}-${perf.date}`;

        if (!sessionMap.has(sessionKey)) {
            // Estimate session duration based on number of exercises
            const sessionExercises = performances.filter(p =>
                p.user_id === perf.user_id && p.date === perf.date
            );

            // Estimate duration: 5 minutes per exercise + 2 minutes rest between exercises
            const estimatedDuration = sessionExercises.length * 5 + (sessionExercises.length - 1) * 2;

            sessionMap.set(sessionKey, {
                id: sessionMap.size + 1,
                date: perf.date,
                duration_in_minutes: estimatedDuration,
                user_id: perf.user_id,
                session_local_id: perf.session_local_id
            });
        }
    });

    return Array.from(sessionMap.values());
}

// Render gender distribution chart
function renderGenderChart(profiles) {
    const ctx = document.getElementById('genderChart');
    if (!ctx) return;

    // Count genders
    const genderCounts = { male: 0, female: 0, other: 0 };
    profiles.forEach(p => {
        if (p.gender) {
            const gender = p.gender.toLowerCase();
            if (genderCounts.hasOwnProperty(gender)) {
                genderCounts[gender]++;
            } else {
                genderCounts.other++;
            }
        } else {
            genderCounts.other++;
        }
    });

    // Destroy previous chart if exists
    if (genderChart) genderChart.destroy();

    genderChart = new Chart(ctx.getContext('2d'), {
        type: 'doughnut',
        data: {
            labels: ['Male', 'Female', 'Other/Not Specified'],
            datasets: [{
                data: [genderCounts.male, genderCounts.female, genderCounts.other],
                backgroundColor: ['#2563eb', '#ec4899', '#64748b'],
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        padding: 20,
                        font: {
                            size: 12
                        }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            const label = context.label || '';
                            const value = context.raw || 0;
                            const total = context.dataset.data.reduce((a, b) => a + b, 0);
                            const percentage = Math.round((value / total) * 100);
                            return `${label}: ${value} (${percentage}%)`;
                        }
                    }
                }
            }
        }
    });
}

// Render age distribution chart
function renderAgeChart(profiles) {
    const ctx = document.getElementById('ageChart');
    if (!ctx) return;

    // Calculate ages - handle text birthday format
    const currentYear = new Date().getFullYear();
    const ages = profiles
        .map(p => {
            if (!p.birthday) return null;

            try {
                const birthDate = new Date(p.birthday);
                const today = new Date();
                let age = today.getFullYear() - birthDate.getFullYear();
                const monthDiff = today.getMonth() - birthDate.getMonth();

                if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
                    age--;
                }

                return age;
            } catch (e) {
                console.error('Error parsing birthday:', p.birthday, e);
                return null;
            }
        })
        .filter(age => age !== null && age > 0 && age < 100);

    // Group into age ranges
    const ageGroups = { "18-24": 0, "25-34": 0, "35-44": 0, "45-54": 0, "55+": 0 };
    ages.forEach(age => {
        if (age < 25) ageGroups["18-24"]++;
        else if (age < 35) ageGroups["25-34"]++;
        else if (age < 45) ageGroups["35-44"]++;
        else if (age < 55) ageGroups["45-54"]++;
        else ageGroups["55+"]++;
    });

    // Destroy previous chart if exists
    if (ageChart) ageChart.destroy();

    ageChart = new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
            labels: Object.keys(ageGroups),
            datasets: [{
                label: 'Number of Users',
                data: Object.values(ageGroups),
                backgroundColor: '#10b981',
                borderRadius: 5
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        precision: 0
                    }
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
}

// Render weekly goal distribution chart
function renderGoalChart(profiles) {
    const ctx = document.getElementById('goalChart');
    if (!ctx) return;

    // Count weekly goals
    const goalCounts = [0, 0, 0, 0, 0, 0, 0];
    profiles.forEach(p => {
        if (p.weekly_goal >= 1 && p.weekly_goal <= 7) {
            goalCounts[p.weekly_goal - 1]++;
        }
    });

    // Destroy previous chart if exists
    if (goalChart) goalChart.destroy();

    goalChart = new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
            labels: ['1 day', '2 days', '3 days', '4 days', '5 days', '6 days', '7 days'],
            datasets: [{
                label: 'Number of Users',
                data: goalCounts,
                backgroundColor: '#6366f1',
                borderRadius: 5
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        precision: 0
                    }
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
}

// Render top exercises chart
function renderExerciseChart(performances) {
    const ctx = document.getElementById('exerciseChart');
    if (!ctx) return;

    // Count exercise usage
    const exerciseCount = {};
    performances.forEach(p => {
        if (p.exercise_name) {
            exerciseCount[p.exercise_name] = (exerciseCount[p.exercise_name] || 0) + 1;
        }
    });

    // Get top 5 exercises
    const topExercises = Object.entries(exerciseCount)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5);

    // Destroy previous chart if exists
    if (exerciseChart) exerciseChart.destroy();

    exerciseChart = new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
            labels: topExercises.map(e => e[0]),
            datasets: [{
                label: 'Times Used',
                data: topExercises.map(e => e[1]),
                backgroundColor: '#f59e0b',
                borderRadius: 5
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            indexAxis: 'y',
            scales: {
                x: {
                    beginAtZero: true,
                    ticks: {
                        precision: 0
                    }
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
}

// Removed: Workout Trends Chart function (renderTrendChart)

// Render workout duration chart
function renderDurationChart(sessions) {
    const ctx = document.getElementById('durationChart');
    if (!ctx) return;

    // Group sessions by duration ranges
    const durationRanges = {
        "< 15 min": 0,
        "15-30 min": 0,
        "30-45 min": 0,
        "45-60 min": 0,
        "> 60 min": 0
    };

    sessions.forEach(s => {
        if (s.duration_in_minutes) {
            const duration = s.duration_in_minutes;
            if (duration < 15) durationRanges["< 15 min"]++;
            else if (duration < 30) durationRanges["15-30 min"]++;
            else if (duration < 45) durationRanges["30-45 min"]++;
            else if (duration < 60) durationRanges["45-60 min"]++;
            else durationRanges["> 60 min"]++;
        }
    });

    // Destroy previous chart if exists
    if (durationChart) durationChart.destroy();

    durationChart = new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
            labels: Object.keys(durationRanges),
            datasets: [{
                label: 'Number of Workouts',
                data: Object.values(durationRanges),
                backgroundColor: '#ef4444',
                borderRadius: 5
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        precision: 0
                    }
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
}

// Render exercise accuracy analysis chart
function renderAccuracyChart(performances) {
    const ctx = document.getElementById('accuracyChart');
    if (!ctx) return;

    // Calculate average accuracy per exercise
    const exerciseAccuracy = {};
    performances.forEach(p => {
        if (!p.planned_reps || p.planned_reps <= 0) return;

        if (!exerciseAccuracy[p.exercise_name]) {
            exerciseAccuracy[p.exercise_name] = { total: 0, count: 0 };
        }

        const accuracy = p.reps_completed / p.planned_reps;
        exerciseAccuracy[p.exercise_name].total += accuracy;
        exerciseAccuracy[p.exercise_name].count += 1;
    });

    const avgAccuracy = Object.entries(exerciseAccuracy).map(([name, data]) => ({
        name,
        accuracy: (data.total / data.count) * 100 // Convert to percentage
    })).sort((a, b) => b.accuracy - a.accuracy);

    // Destroy previous chart if exists
    if (accuracyChart) accuracyChart.destroy();

    accuracyChart = new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
            labels: avgAccuracy.map(e => e.name),
            datasets: [{
                label: 'Average Accuracy (%)',
                data: avgAccuracy.map(e => e.accuracy),
                backgroundColor: avgAccuracy.map(e =>
                    e.accuracy > 80 ? '#3b82f6' : e.accuracy > 60 ? '#f59e0b' : '#ef4444'
                )
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100,
                    title: {
                        display: true,
                        text: 'Accuracy (%)'
                    }
                }
            }
        }
    });
}

// Render high-risk exercises chart
function renderRiskChart(performances) {
    const ctx = document.getElementById('riskChart');
    if (!ctx) return;

    // Group by exercise
    const exerciseStats = {};
    performances.forEach(p => {
        if (!p.planned_reps || p.planned_reps <= 0) return;

        if (!exerciseStats[p.exercise_name]) {
            exerciseStats[p.exercise_name] = {
                totalAccuracy: 0,
                count: 0,
                lowAccuracyCount: 0
            };
        }

        const accuracy = p.reps_completed / p.planned_reps;
        exerciseStats[p.exercise_name].totalAccuracy += accuracy;
        exerciseStats[p.exercise_name].count += 1;
        if (accuracy < 0.6) exerciseStats[p.exercise_name].lowAccuracyCount += 1;
    });

    // Calculate risk score (low accuracy % * popularity)
    const riskData = Object.entries(exerciseStats).map(([name, data]) => ({
        name,
        avgAccuracy: (data.totalAccuracy / data.count) * 100,
        popularity: data.count,
        riskScore: (data.lowAccuracyCount / data.count) * 100 * Math.log(data.count)
    })).sort((a, b) => b.riskScore - a.riskScore).slice(0, 8);

    // Destroy previous chart if exists
    if (riskChart) riskChart.destroy();

    riskChart = new Chart(ctx.getContext('2d'), {
        type: 'bar',
        data: {
            labels: riskData.map(e => e.name),
            datasets: [{
                label: 'Risk Score',
                data: riskData.map(e => e.riskScore),
                backgroundColor: riskData.map(e =>
                    e.avgAccuracy > 75 ? '#3b82f6' : e.avgAccuracy > 60 ? '#f59e0b' : '#ef4444'
                )
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            indexAxis: 'y',
            scales: {
                x: {
                    title: {
                        display: true,
                        text: 'Risk Score (Low Accuracy × Popularity)'
                    }
                }
            }
        }
    });
}

// Function to load and render the Users Progress table
function renderUsersProgressTable(profiles, performances, sessions) {
    const tableBody = document.querySelector('#usersProgressTable tbody');
    if (!tableBody) return;

    // Clear existing rows
    tableBody.innerHTML = '';

    // --- 1. Aggregate Performance Data by User ---
    const userStats = {};

    // Calculate total workouts and average accuracy
    sessions.forEach(session => {
        // Use 'user_id' from session data which is derived from performance
        if (!userStats[session.user_id]) {
            userStats[session.user_id] = {
                totalWorkouts: 0,
                totalAccuracySum: 0,
                accuracyCount: 0,
                recentAccuracy: [] // Not needed anymore but keep for aggregation
            };
        }
        userStats[session.user_id].totalWorkouts++;
    });

    performances.forEach(p => {
        // Use 'user_id', 'planned_reps', 'reps_completed', and 'date' from session_performance table
        if (!userStats[p.user_id] || p.planned_reps <= 0) return;

        const accuracy = p.reps_completed / p.planned_reps;
        userStats[p.user_id].totalAccuracySum += accuracy;
        userStats[p.user_id].accuracyCount++;
    });

    // --- 2. Process and Render Profiles ---
    profiles.forEach(profile => {
        // Use 'id' and 'nickname' from the profiles table
        const stats = userStats[profile.id] || { totalWorkouts: 0, totalAccuracySum: 0, accuracyCount: 0 };
        const totalWorkouts = stats.totalWorkouts;
        const avgAccuracy = stats.accuracyCount > 0 ? (stats.totalAccuracySum / stats.accuracyCount) * 100 : 0;

        // --- 3. Determine Overall Status (Simplified) ---
        let overallStatus = 'Good';
        let statusClass = 'status-good';

        if (totalWorkouts === 0) {
            overallStatus = 'Inactive';
            statusClass = 'status-inactive';
        } else if (avgAccuracy < 70) {
            overallStatus = 'Needs Attention';
            statusClass = 'status-warning';
        }

        // --- 4. Create Table Row ---
        const row = tableBody.insertRow();
        row.innerHTML = `
            <td>${profile.nickname || 'N/A'}</td>
            <td>${totalWorkouts}</td>
            <td>${avgAccuracy.toFixed(1)}%</td>
            <td><span class="${statusClass}">${overallStatus}</span></td>
        `;
    });

    // NOTE: Removed all logic for populating user select and adding 'View Trend' listeners.
}

// NOTE: Removed all User Performance History related functions:
// - populateUserSelect
// - loadUserPerformanceHistory
// - renderUserAccuracyChart
// - renderUserPerformanceTable

// Export data to CSV
function exportData() {
    try {
        // Create CSV content
        let csvContent = "data:text/csv;charset=utf-8,";

        // Add header
        csvContent += "User ID,Nickname,Gender,Age,Weekly Goal,Total Workouts,Avg Performance\n";

        // This is a simplified export - in a real implementation, 
        // you would fetch the actual data and format it properly

        // Create download link
        const encodedUri = encodeURI(csvContent);
        const link = document.createElement("a");
        link.setAttribute("href", encodedUri);
        link.setAttribute("download", `fitness_tracker_data_${new Date().toISOString().split('T')[0]}.csv`);
        document.body.appendChild(link);

        // Trigger download
        link.click();

        // Clean up
        document.body.removeChild(link);
    } catch (error) {
        console.error('Error exporting data:', error);
        showError(`Failed to export data: ${error.message}`);
    }
}