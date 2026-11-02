# Keep rules for release builds (R8 shrinking is enabled in build.gradle.kts).

# WorkManager (pulled in by the Google Mobile Ads SDK) uses Room, which
# instantiates its generated *_Impl database classes by reflection.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# Native Google sign-in (google_sign_in uses Credential Manager).
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }
